import Foundation

/// 把解码后的 StateEvent 应用到 SessionRegistry 的胶水。
/// 所有方法 @MainActor 保证只在主队列改 registry。
@MainActor
public final class EventRouter {
    private unowned let registry: SessionRegistry
    private let permissionPrompter: PermissionPrompter

    // 子 agent 识别（v0.x，因 Claude Code 还未稳定暴露 agent_id/parent_session_id）：
    // 用 transcript_path 做"一个 chat panel 一个气泡"的归并 ——
    //   - 第一次见到某 transcript_path 的 session_id 视为该 panel 的主 agent；
    //   - 同 transcript_path 的其他 session_id 视为子 agent，事件直接丢弃。
    // transcript_path 不一定每条事件都带，所以缓存 session_id → transcript_path 以便后续事件查回。
    private var transcriptToPrimary: [String: String] = [:]
    private var sessionToTranscript: [String: String] = [:]

    public init(registry: SessionRegistry, permissionPrompter: PermissionPrompter) {
        self.registry = registry
        self.permissionPrompter = permissionPrompter
    }

    private func transcriptPath(of event: StateEvent) -> String? {
        event.stringValue(forKey: "transcript_path")
    }

    private func isSubagentEvent(_ event: StateEvent) -> Bool {
        // hopet-emit 在 hook payload 缺 session_id 时会兜底生成 anon-XXXX；
        // 这种事件无法跨事件追踪，视为子 agent / 噪声直接丢弃，避免每次都建新气泡。
        if event.sessionId.hasPrefix("anon-") { return true }
        // 显式信号优先（Claude Code 未来若直接暴露 agent_id 之类会被 hopet-emit 转成 isSubagent=true）。
        if event.isSubagent == true { return true }
        // transcript_path 兜底识别。
        let tp = transcriptPath(of: event) ?? sessionToTranscript[event.sessionId]
        guard let tp, !tp.isEmpty else { return false }
        sessionToTranscript[event.sessionId] = tp
        if let primary = transcriptToPrimary[tp] {
            return primary != event.sessionId
        } else {
            transcriptToPrimary[tp] = event.sessionId
            return false
        }
    }

    private func cleanupMaps(removedSessionId: String) {
        guard let tp = sessionToTranscript.removeValue(forKey: removedSessionId) else { return }
        // 主 agent 结束时把同 transcript 下所有（含子 agent）缓存一并清掉，避免长期堆积。
        if transcriptToPrimary[tp] == removedSessionId {
            transcriptToPrimary.removeValue(forKey: tp)
            sessionToTranscript = sessionToTranscript.filter { $0.value != tp }
        }
    }

    /// 直接喂入 StateEvent。
    public func handle(_ event: StateEvent) {
        let sid = event.sessionId.hopetShortId
        let evt = event.event.rawValue
        // 子 agent（Task 工具触发的子上下文）不进 registry，不显示气泡。
        // 一个用户会话只有一个气泡，子 agent 的活动通过父 session 的状态体现。
        if isSubagentEvent(event) {
            HopetLog.trace("skip", "reason=subagent sid=\(sid) evt=\(evt) tool=\(event.tool.rawValue)")
            return
        }
        HopetLog.trace("event", "tool=\(event.tool.rawValue) evt=\(evt) sid=\(sid)")
        switch event.event {
        case .sessionStart:
            handleSessionStart(event)
        case .sessionEnd:
            registry.remove(event.sessionId)
            cleanupMaps(removedSessionId: event.sessionId)
        default:
            handleStateEvent(event)
        }
        // 任何事件（除 sessionEnd 已经移除）都刷新活跃时间戳。
        if event.event != .sessionEnd {
            registry.patch(event.sessionId) { s in
                s.lastActivityAt = event.timestamp
            }
        }
    }

    /// 喂入原始 JSON Data（来自 socket）+ 可回写决策的 reply 闭包。
    /// permission_ask + 携带 requestId 的事件会挂起 reply，等用户在气泡上做决定。
    /// AskUserQuestion（tool_name == "AskUserQuestion"）也通过 PermissionRequest hook 进来，
    /// 走结构化 elicitation 路径：回包带 updatedInput.answers。
    public func handleRaw(_ data: Data, reply: @escaping @Sendable (Data?) -> Void) {
        do {
            let event = try Self.decoder.decode(StateEvent.self, from: data)
            let subagent = isSubagentEvent(event)
            handle(event)
            if event.event == .permissionAsk, event.requestId != nil, !subagent {
                let sidShort = event.sessionId.hopetShortId
                let reqShort = event.requestId!.hopetShortId
                if isAskUserQuestion(event) {
                    HopetLog.trace("askuser", "enqueue sid=\(sidShort) reqId=\(reqShort)")
                    permissionPrompter.enqueueAskUser(event, reply: reply)
                } else {
                    HopetLog.trace("perm", "enqueue sid=\(sidShort) reqId=\(reqShort)")
                    permissionPrompter.enqueue(event, reply: reply)
                }
            } else {
                reply(nil)
            }
        } catch {
            HopetLog.trace("error", "decode StateEvent failed: \(error)")
            reply(nil)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func isAskUserQuestion(_ event: StateEvent) -> Bool {
        event.stringValue(forKey: "tool_name") == "AskUserQuestion"
    }

    // MARK: -

    private func handleSessionStart(_ event: StateEvent) {
        let session = Session(
            id: event.sessionId,
            tool: event.tool,
            cwd: event.cwd ?? FileManager.default.currentDirectoryPath,
            terminalApp: event.terminalApp,
            terminalTty: event.terminalTty,
            terminalSessionId: event.terminalSessionId,
            startedAt: event.timestamp,
            currentState: .idle,
            stateSince: event.timestamp
        )
        registry.upsert(session)
    }

    private func handleStateEvent(_ event: StateEvent) {
        // 若 session 不存在（外部启动 + 跳过 SessionStart），按需即时创建。
        if registry.session(event.sessionId) == nil {
            let session = Session(
                id: event.sessionId,
                tool: event.tool,
                cwd: event.cwd ?? FileManager.default.currentDirectoryPath,
                terminalApp: event.terminalApp,
                startedAt: event.timestamp,
                currentState: .idle,
                stateSince: event.timestamp
            )
            registry.upsert(session)
        }

        // 用 event 携带的细节更新 session 字段。
        registry.patch(event.sessionId) { s in
            if let cwd = event.cwd { s.cwd = cwd }
            // 终端信息：以最近一次有值的 event 为准（旧 session restore 后也能补全）。
            if let app = event.terminalApp { s.terminalApp = app }
            if let tty = event.terminalTty { s.terminalTty = tty }
            if let tsid = event.terminalSessionId { s.terminalSessionId = tsid }

            switch event.event {
            case .userPrompt:
                if let snippet = event.stringValue(forKey: "prompt") {
                    s.lastPromptSnippet = String(snippet.prefix(256))
                    if s.title == nil {
                        s.title = String(snippet.prefix(32))
                    }
                }
            case .askUser:
                let q = event.stringValue(forKey: "tool_input.question")
                       ?? event.stringValue(forKey: "message")
                       ?? "Claude 在等你回答"
                s.pendingQuestion = q
            case .askUserResolved:
                s.pendingQuestion = nil
                s.pendingAskUser = nil
            default:
                break
            }
        }

        if let next = SessionStateMachine.nextState(
            from: registry.session(event.sessionId)?.currentState ?? .idle,
            event: event.event
        ) {
            registry.transition(sessionId: event.sessionId, to: next, at: event.timestamp)
        }
    }
}
