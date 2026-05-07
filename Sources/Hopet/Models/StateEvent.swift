import Foundation

/// IPC 协议事件类型，与 hooks-and-priority.md §1.1 一一对应。
public enum EventKind: String, Codable, Sendable {
    case sessionStart    = "session_start"
    case sessionEnd      = "session_end"
    case userPrompt      = "user_prompt"
    case preToolUse      = "pre_tool_use"
    case postToolUse     = "post_tool_use"
    case thinkingStart   = "thinking_start"
    case permissionAsk   = "permission_ask"
    case askUser         = "ask_user"
    case askUserResolved = "ask_user_resolved"
    case stop            = "stop"
    case error           = "error"
}

/// hopet-emit → hopetd.sock 的单向 payload。schema = 1。
/// `requestId` 仅在需要服务端反向回写决策的事件（v0.1：permission_ask）上出现。
public struct StateEvent: Codable, Sendable {
    public let schema: Int
    public let sessionId: String
    public let tool: AITool
    public let event: EventKind
    public let timestamp: Date
    public let cwd: String?
    public let terminalApp: String?
    public let terminalTty: String?
    public let terminalSessionId: String?
    public let payload: [String: AnyCodable]?
    public let requestId: String?
    /// hopet-emit 侧根据 hook payload 中的 agent_id / subagent_id / parent_session_id 等信号识别。
    /// Hopet 收到后直接跳过 registry，不创建/不显示气泡。
    public let isSubagent: Bool?

    public init(
        sessionId: String,
        tool: AITool,
        event: EventKind,
        timestamp: Date = Date(),
        cwd: String? = nil,
        terminalApp: String? = nil,
        terminalTty: String? = nil,
        terminalSessionId: String? = nil,
        payload: [String: AnyCodable]? = nil,
        requestId: String? = nil,
        isSubagent: Bool? = nil
    ) {
        self.schema = 1
        self.sessionId = sessionId
        self.tool = tool
        self.event = event
        self.timestamp = timestamp
        self.cwd = cwd
        self.terminalApp = terminalApp
        self.terminalTty = terminalTty
        self.terminalSessionId = terminalSessionId
        self.payload = payload
        self.requestId = requestId
        self.isSubagent = isSubagent
    }
}

/// Hopet → hopet-emit 的反向响应（permission_ask / AskUserQuestion 同步回写共用）。
///
/// - 普通权限：`decision = "allow" | "deny" | "ask"`，不填 `updatedInput`。
/// - AskUserQuestion：`decision = "allow"` + `updatedInput`（带 `answers`），
///   hopet-emit 会把它放进 Claude 期望的 `hookSpecificOutput.decision.updatedInput`。
public struct PermissionResponse: Codable, Sendable {
    public let schema: Int
    public let requestId: String
    /// "allow" | "deny" | "ask"。"ask" 表示让 Claude 走自己的终端 UI。
    public let decision: String
    public let reason: String?
    public let updatedInput: AnyCodable?

    public init(requestId: String, decision: String, reason: String? = nil, updatedInput: AnyCodable? = nil) {
        self.schema = 1
        self.requestId = requestId
        self.decision = decision
        self.reason = reason
        self.updatedInput = updatedInput
    }

    private enum CodingKeys: String, CodingKey {
        case schema, requestId, decision, reason, updatedInput
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(decision, forKey: .decision)
        if let reason { try c.encode(reason, forKey: .reason) }
        if let updatedInput { try c.encode(updatedInput, forKey: .updatedInput) }
    }
}

extension StateEvent {
    /// 按字段名取 payload 值：先尝试平铺 key，再尝试点号嵌套路径（与 hopet-emit 的白名单输出兼容）。
    public func anyValue(forKey key: String) -> Any? {
        guard let raw = payload?.mapValues({ $0.value }) else { return nil }
        if let v = raw[key] { return v }
        return AnyCodable.value(at: key, in: raw)
    }

    public func stringValue(forKey key: String) -> String? {
        anyValue(forKey: key) as? String
    }

    /// 返回一个仅替换 `event` 字段的副本，用于 router 入口的事件归一化。
    public func normalized(event newEvent: EventKind) -> StateEvent {
        StateEvent(
            sessionId: sessionId,
            tool: tool,
            event: newEvent,
            timestamp: timestamp,
            cwd: cwd,
            terminalApp: terminalApp,
            terminalTty: terminalTty,
            terminalSessionId: terminalSessionId,
            payload: payload,
            requestId: requestId,
            isSubagent: isSubagent
        )
    }

    /// 替换 sessionId 并清掉 isSubagent 标记的副本。
    /// 用于把 subagent 触发的同步类 hook（permission_ask / askUser）路由到所属 transcript 的
    /// 主 session 上挂气泡——子 agent 的工具调用从用户视角仍是"主会话在等你回答"。
    public func reroute(toSessionId newId: String) -> StateEvent {
        StateEvent(
            sessionId: newId,
            tool: tool,
            event: event,
            timestamp: timestamp,
            cwd: cwd,
            terminalApp: terminalApp,
            terminalTty: terminalTty,
            terminalSessionId: terminalSessionId,
            payload: payload,
            requestId: requestId,
            isSubagent: false
        )
    }
}
