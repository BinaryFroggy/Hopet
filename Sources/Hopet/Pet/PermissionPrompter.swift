import AppKit
import Foundation

/// 处理两条同步挂起的 hook 应答路径：
///   1. PermissionRequest（一般工具调用）→ 用户在气泡上点 Allow/Deny → 回包 `{behavior}`。
///   2. PermissionRequest（tool_name == "AskUserQuestion"）→ 用户在气泡上填答案 → 回包
///      `{behavior:"allow", updatedInput:{...原 tool_input, answers:{...}}}`。
///
/// 两条路径共用一张 `pending: requestId → reply` 表，由不同的 enqueue/resolve 入口区分。
@MainActor
public final class PermissionPrompter {
    private unowned let registry: SessionRegistry
    private var pending: [String: @Sendable (Data?) -> Void] = [:]

    public init(registry: SessionRegistry) {
        self.registry = registry
    }

    // MARK: - Permission（普通工具调用）

    /// SocketServer 收到 permission_ask 帧后调用（非 AskUserQuestion 走这条）。
    public func enqueue(_ event: StateEvent, reply: @escaping @Sendable (Data?) -> Void) {
        guard let requestId = event.requestId, !requestId.isEmpty else {
            reply(nil)
            return
        }

        let toolName = event.stringValue(forKey: "tool_name") ?? "Unknown"
        let command  = event.stringValue(forKey: "tool_input.command")
        let filePath = event.stringValue(forKey: "tool_input.file_path")

        pending[requestId] = reply
        registry.patch(event.sessionId) { s in
            s.pendingPermission = PendingPermission(
                requestId: requestId,
                toolName: toolName,
                command: command,
                filePath: filePath
            )
        }
    }

    /// 用户在气泡上点击决策后调用。decision ∈ {"allow", "deny", "ask"}。
    /// "ask" 表示让 Claude 走它自己的终端 UI（hopet-emit 输出 {} 让出主导权）。
    public func resolve(sessionId: String, requestId: String, decision: String) {
        let sid = sessionId.hopetShortId
        let rid = requestId.hopetShortId
        guard let reply = pending.removeValue(forKey: requestId) else {
            // 已经超时被 socket 兜底关闭；只清 UI 即可。
            HopetLog.trace("resolve", "STALE sid=\(sid) reqId=\(rid) decision=\(decision)")
            registry.patch(sessionId) { s in
                if s.pendingPermission?.requestId == requestId {
                    s.pendingPermission = nil
                }
            }
            return
        }
        HopetLog.trace("resolve", "sid=\(sid) reqId=\(rid) decision=\(decision)")
        let payload = PermissionResponse(requestId: requestId, decision: decision)
        reply(encodeResponse(payload))

        registry.patch(sessionId) { s in
            if s.pendingPermission?.requestId == requestId {
                s.pendingPermission = nil
            }
        }
    }

    // MARK: - AskUserQuestion（elicitation）

    /// SocketServer 收到 permission_ask 帧且 `tool_name == "AskUserQuestion"` 时走这里。
    public func enqueueAskUser(_ event: StateEvent, reply: @escaping @Sendable (Data?) -> Void) {
        guard let requestId = event.requestId, !requestId.isEmpty else {
            reply(nil)
            return
        }

        let toolInputDict = (event.anyValue(forKey: "tool_input") as? [String: Any]) ?? [:]
        let questions = parseQuestions(toolInputDict["questions"])
        let originalJSON = (try? JSONSerialization.data(withJSONObject: toolInputDict, options: [])) ?? Data()

        // 同时清掉早先 PreToolUse fire-and-forget 设的简单 pendingQuestion，避免气泡内容冲突。
        pending[requestId] = reply
        registry.patch(event.sessionId) { s in
            s.pendingQuestion = nil
            s.pendingAskUser = PendingAskUser(
                requestId: requestId,
                questions: questions,
                originalToolInputJSON: originalJSON
            )
        }
    }

    /// 用户提交答案。answers 形如 `{ "问题文案": "回答" }`，对应 questions 顺序映射。
    /// 同时也支持 cancel：传 cancel = true 时回 deny，让 Claude 走自身 UI。
    public func resolveAskUser(sessionId: String, requestId: String, answers: [String: String], cancel: Bool = false) {
        let sid = sessionId.hopetShortId
        let rid = requestId.hopetShortId
        guard let reply = pending.removeValue(forKey: requestId) else {
            HopetLog.trace("askuser", "STALE sid=\(sid) reqId=\(rid) cancel=\(cancel)")
            registry.patch(sessionId) { s in
                if s.pendingAskUser?.requestId == requestId {
                    s.pendingAskUser = nil
                }
            }
            return
        }

        // 默认行为：cancel → deny；否则 → allow + updatedInput。
        let response: PermissionResponse
        if cancel {
            HopetLog.trace("askuser", "resolve sid=\(sid) reqId=\(rid) decision=deny(cancel)")
            response = PermissionResponse(requestId: requestId, decision: "deny", reason: "User cancelled")
        } else if let pending = registry.session(sessionId)?.pendingAskUser,
                  pending.requestId == requestId {
            HopetLog.trace("askuser", "resolve sid=\(sid) reqId=\(rid) decision=allow answers=\(answers.count)")
            let merged = mergeAnswers(into: pending.originalToolInputJSON, answers: answers)
            response = PermissionResponse(
                requestId: requestId,
                decision: "allow",
                updatedInput: AnyCodable(merged)
            )
        } else {
            HopetLog.trace("askuser", "STALE-pending sid=\(sid) reqId=\(rid)")
            response = PermissionResponse(requestId: requestId, decision: "deny", reason: "Stale request")
        }

        reply(encodeResponse(response))

        registry.patch(sessionId) { s in
            if s.pendingAskUser?.requestId == requestId {
                s.pendingAskUser = nil
            }
        }
    }

    // MARK: - Helpers

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private func encodeResponse(_ resp: PermissionResponse) -> Data {
        (try? Self.encoder.encode(resp)) ?? Data()
    }

    /// 把用户填的 answers 合并进原 tool_input：`{ ...原 tool_input, answers: {...} }`。
    private func mergeAnswers(into originalJSON: Data, answers: [String: String]) -> [String: Any] {
        var dict = (try? JSONSerialization.jsonObject(with: originalJSON) as? [String: Any]) ?? [:]
        dict["answers"] = answers
        return dict
    }

    /// 解析 tool_input.questions 数组，与 clawd-on-desk 的 elicitation schema 对齐。
    /// 接受形如 `[{question, options:[{label}|String], multiSelect}]`。
    private func parseQuestions(_ raw: Any?) -> [AskUserQuestionItem] {
        guard let arr = raw as? [Any] else { return [] }
        return arr.compactMap { item in
            guard let dict = item as? [String: Any],
                  let q = dict["question"] as? String, !q.isEmpty else { return nil }
            let options: [String]? = {
                guard let opts = dict["options"] as? [Any] else { return nil }
                let labels: [String] = opts.compactMap { o in
                    if let s = o as? String { return s }
                    if let d = o as? [String: Any] {
                        return (d["label"] as? String) ?? (d["value"] as? String)
                    }
                    return nil
                }
                return labels.isEmpty ? nil : labels
            }()
            let multi = dict["multiSelect"] as? Bool
            return AskUserQuestionItem(question: q, options: options, multiSelect: multi)
        }
    }
}
