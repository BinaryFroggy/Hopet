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
            // session 正常结束但还挂着 pendingPermission / pendingAskUser 的场景：
            // 用户在终端直接关掉 Claude，PostToolUse / askUserResolved 不会到达，
            // 不显式 cancel 会让 pending reply 闭包永远留在表里，等价于 socket fd 泄漏。
            permissionPrompter.cancelPending(sessionId: event.sessionId)
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
    ///
    /// 子 agent 处理：fire-and-forget（pre/post tool use 等）丢弃避免气泡爆炸；
    /// 但 permission_ask / askUser 这两类用户必须回答的同步事件，**重路由**到所属 transcript 的主
    /// session 上挂气泡——否则 Hopet 完全沉默而 Claude 弹自己的 fallback UI，体验割裂。
    public func handleRaw(_ data: Data, reply: @escaping @Sendable (Data?) -> Void) {
        do {
            let raw = try Self.decoder.decode(StateEvent.self, from: data)
            // AskUserQuestion 在 hook 协议里是 permission_ask + tool_name="AskUserQuestion"。
            // 在 router 入口归一为 .askUser，下游（状态机、enqueue 分支）只看 EventKind。
            let isAskUser = raw.event == .permissionAsk && isAskUserQuestion(raw)
            let normalized = isAskUser ? raw.normalized(event: .askUser) : raw

            // 跑一次副作用：transcriptToPrimary 表会被填充，subagent 标记被算出。
            let subagent = isSubagentEvent(normalized)
            // 同步类必须有 requestId 才进 enqueue；没 requestId 的退化为 fire-and-forget。
            let isSyncRequest = (normalized.event == .permissionAsk || normalized.event == .askUser)
                && normalized.requestId != nil

            // 子 agent 的 fire-and-forget：保留原"丢弃 + reply nil"。trace 由 handle() 写一行。
            if subagent && !isSyncRequest {
                handle(normalized)
                reply(nil)
                return
            }

            // 子 agent 的同步请求：重路由到主 session（同 transcript_path 上首个 main agent）。
            // 找不到主 session（e.g. 主 agent 还没发 SessionStart）就 fallback 用 subagent 自己的 sid，
            // 等于在主 sid 缺失时退化成 v0 行为；无论如何不让用户看不到气泡。
            let routed: StateEvent
            if subagent, let primary = primarySessionId(forTranscriptOf: normalized),
               primary != normalized.sessionId {
                HopetLog.trace("reroute",
                    "sub→primary subSid=\(normalized.sessionId.hopetShortId) primary=\(primary.hopetShortId) evt=\(normalized.event.rawValue)")
                routed = normalized.reroute(toSessionId: primary)
            } else {
                routed = normalized
            }

            handle(routed)
            if routed.requestId != nil {
                let sidShort = routed.sessionId.hopetShortId
                let reqShort = routed.requestId!.hopetShortId
                switch routed.event {
                case .askUser:
                    HopetLog.trace("askuser", "enqueue sid=\(sidShort) reqId=\(reqShort)")
                    permissionPrompter.enqueueAskUser(routed, reply: reply)
                case .permissionAsk:
                    HopetLog.trace("perm", "enqueue sid=\(sidShort) reqId=\(reqShort)")
                    permissionPrompter.enqueue(routed, reply: reply)
                default:
                    reply(nil)
                }
            } else {
                reply(nil)
            }
        } catch {
            HopetLog.trace("error", "decode StateEvent failed: \(error)")
            reply(nil)
        }
    }

    /// 返回 event 所属 transcript_path 上已注册的主 session id。
    /// `isSubagentEvent` 已经把 transcriptToPrimary 表填好了，这里只是查表。
    private func primarySessionId(forTranscriptOf event: StateEvent) -> String? {
        let tp = transcriptPath(of: event) ?? sessionToTranscript[event.sessionId]
        guard let tp else { return nil }
        return transcriptToPrimary[tp]
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
        pruneStaleSiblings(of: session)
    }

    /// 同一 (tool, cwd) 下若已有旧 session，视作上一次没收到 session_end 的躺尸气泡，在新 session_start
    /// 时清掉。漏发 SessionEnd 的常见场景：宿主被强关、Hopet 启停错位、IDE extension host 重载导致
    /// claude-code 子进程换 PID + 换 sid。不清的话用户就会看到"一个会话却有多个气泡"。
    ///
    /// 区分两类同 cwd 的旧 session：
    /// - IDE 内嵌（terminalTty == nil）：extension host 独占该项目目录的 claude-code 实例，新 session_start
    ///   必然是替身，无视状态一律清。
    /// - 真终端（terminalTty != nil）：iTerm / Ghostty 多 tab 可能合法并发，仅清确实闲下来的；
    ///   仍在运行的（PetState.isRunning == true）保留。
    private func pruneStaleSiblings(of new: Session) {
        let victims = registry.activeSessions(of: new.tool).filter { other in
            guard other.id != new.id, other.cwd == new.cwd else { return false }
            // IDE 内嵌（无 tty）→ 一律清；真终端 → 只清非运行中的。
            return other.terminalTty == nil || !other.currentState.isRunning
        }
        for v in victims {
            let host = v.terminalTty.map { "tty=\($0)" } ?? "ide-embedded"
            HopetLog.trace("autoprune", "remove stale peer sid=\(v.id.hopetShortId) cwd=\(new.cwd) state=\(v.currentState.rawValue) host=\(host) (replaced by sid=\(new.id.hopetShortId))")
            permissionPrompter.cancelPending(sessionId: v.id)
            registry.remove(v.id)
            cleanupMaps(removedSessionId: v.id)
        }
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
            default:
                break
            }
        }

        // 外部（终端 UI / Claude 自身）处理完待决策的信号：
        // - postToolUse：上次 PermissionRequest 对应的工具已经真正执行（用户在终端 allow）。
        // - error：工具失败（包括用户在终端 deny / 终端取消）。
        // - askUserResolved：AskUserQuestion 已被回答（不管在哪一侧）。
        // 三种情况下都把气泡上的待决策清掉，避免气泡停留成"假活"按钮。
        switch event.event {
        case .postToolUse, .error, .askUserResolved:
            permissionPrompter.cancelPending(sessionId: event.sessionId)
        default:
            break
        }

        if let next = SessionStateMachine.nextState(
            from: registry.session(event.sessionId)?.currentState ?? .idle,
            event: event.event
        ) {
            registry.transition(sessionId: event.sessionId, to: next, at: event.timestamp)
        }
    }
}
