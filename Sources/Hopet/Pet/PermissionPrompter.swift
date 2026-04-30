import AppKit
import Foundation

/// 处理两条同步挂起的 hook 应答路径：
///   1. PermissionRequest（一般工具调用）→ 用户在气泡上点 Allow/Deny → 回包 `{behavior}`。
///   2. PermissionRequest（tool_name == "AskUserQuestion"）→ 用户在气泡上填答案 → 回包
///      `{behavior:"allow", updatedInput:{...原 tool_input, answers:{...}}}`。
///
/// 两条路径共用一张 `pending: requestId → reply` 表，由不同的 enqueue/resolve 入口区分。
///
/// 不主动超时：用户不点 → 气泡一直显示。hopet-emit 30s 后自己会 fall back 到终端 UI（输出 `{}`），
/// 之后用户在终端里 allow/deny 完，Claude 会触发 PostToolUse / PostToolUseFailure，
/// EventRouter 收到这些事件时调 `cancelPending(sessionId:)` 主动把对应气泡清掉。
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
        // ExitPlanMode 走通用 permission_ask hook，但 tool_input 里挂的是整段 plan markdown。
        // trim + 截断在这里完成一次：气泡侧 1Hz 重渲染下避免反复扫描多 KB 文本，
        // 同时 16 KiB 上限保护异常长度的 payload（IPC 帧本身有 1 MiB 上限，但展示框装不下）。
        let plan: String? = {
            guard toolName == PendingPermission.exitPlanModeTool,
                  let raw = event.stringValue(forKey: "tool_input.plan") else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(16_384))
        }()

        pending[requestId] = reply
        registry.patch(event.sessionId) { s in
            s.pendingPermission = PendingPermission(
                requestId: requestId,
                toolName: toolName,
                command: command,
                filePath: filePath,
                plan: plan
            )
        }
    }

    /// 用户在气泡上点击决策后调用。decision ∈ {"allow", "deny", "ask"}。
    /// "ask" 表示让 Claude 走它自己的终端 UI（hopet-emit 输出 {} 让出主导权）。
    /// `reason` 仅在 deny 时附给 Claude 的反馈文本（例如 plan-approval 的 "继续规划" 或自定义反馈）。
    public func resolve(sessionId: String, requestId: String, decision: String, reason: String? = nil) {
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
        let payload = PermissionResponse(requestId: requestId, decision: decision, reason: reason)
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

        // 乐观切回 responding：用户在气泡上作答即视作 askUser 解决，不等远端 PostToolUse
        // 投递的 ask_user_resolved 帧。否则在 hook 漏发 / 宿主无 PostToolUse（如手工触发）
        // 的场景下，宠物会卡在 ask-user 动画。状态机里 (.responding, .askUserResolved) → nil，
        // 远端帧后续真到达也是 no-op，幂等。
        if let session = registry.session(sessionId),
           let next = SessionStateMachine.nextState(from: session.currentState, event: .askUserResolved) {
            registry.transition(sessionId: sessionId, to: next)
        }
    }

    // MARK: - External resolution

    /// EventRouter 在收到 postToolUse / error / askUserResolved 时调用：
    /// 表示该 session 上的待决策已经被外部（终端 UI / Claude 自身）处理过，
    /// Hopet 这边只需把对应 pending 表项 + 气泡上的待决策标记清掉即可。
    /// 调 reply(nil) 让 SocketServer 关闭 fd —— 既释放资源，又让 hopet-emit
    /// 端的阻塞 read 读到 EOF 后输出 `{}` 收尾退出。
    public func cancelPending(sessionId: String) {
        guard let session = registry.session(sessionId) else { return }
        // 没有任何待决策项时直接退出，避免每个 postToolUse / error 都触发 registry.patch 引发全树重渲染。
        guard session.pendingPermission != nil
            || session.pendingAskUser != nil
            || session.pendingQuestion != nil else { return }

        let sid = sessionId.hopetShortId
        if let pp = session.pendingPermission, let reply = pending.removeValue(forKey: pp.requestId) {
            HopetLog.trace("auto-cancel", "sid=\(sid) reqId=\(pp.requestId.hopetShortId) (resolved externally)")
            reply(nil)
        }
        if let pa = session.pendingAskUser, let reply = pending.removeValue(forKey: pa.requestId) {
            HopetLog.trace("auto-cancel", "sid=\(sid) reqId=\(pa.requestId.hopetShortId) (resolved externally)")
            reply(nil)
        }
        registry.patch(sessionId) { s in
            s.pendingPermission = nil
            s.pendingAskUser = nil
            s.pendingQuestion = nil
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
    /// 接受形如 `[{question, options:[{label, description}|String], multiSelect}]`。
    /// description 缺省时回退为 nil，兼容只有 label 的旧投递。
    private func parseQuestions(_ raw: Any?) -> [AskUserQuestionItem] {
        guard let arr = raw as? [Any] else { return [] }
        return arr.compactMap { item in
            guard let dict = item as? [String: Any],
                  let q = dict["question"] as? String, !q.isEmpty else { return nil }
            let options: [AskUserQuestionOption]? = {
                guard let opts = dict["options"] as? [Any] else { return nil }
                let parsed: [AskUserQuestionOption] = opts.compactMap { o in
                    if let s = o as? String { return AskUserQuestionOption(label: s) }
                    if let d = o as? [String: Any] {
                        guard let label = (d["label"] as? String) ?? (d["value"] as? String) else { return nil }
                        let desc = (d["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        return AskUserQuestionOption(label: label, description: desc)
                    }
                    return nil
                }
                return parsed.isEmpty ? nil : parsed
            }()
            let multi = dict["multiSelect"] as? Bool
            return AskUserQuestionItem(question: q, options: options, multiSelect: multi)
        }
    }
}
