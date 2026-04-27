import Foundation

extension String {
    /// hopet 内部日志展示用：取前 8 字符作为短 id 前缀。
    var hopetShortId: String { String(prefix(8)) }
}

/// 一次未决的权限请求（Claude PermissionRequest hook 触发）。
/// requestId 是 hopet-emit 生成、Hopet 通过 socket 反向回写决策时必须带上的 token。
public struct PendingPermission: Codable, Sendable, Hashable {
    public let requestId: String
    public let toolName: String
    public let command: String?
    public let filePath: String?

    public init(requestId: String, toolName: String, command: String? = nil, filePath: String? = nil) {
        self.requestId = requestId
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
    }
}

/// AskUserQuestion (elicitation) 的单个问题项。
public struct AskUserQuestionItem: Codable, Sendable, Hashable {
    public let question: String
    public let options: [String]?
    public let multiSelect: Bool?

    public init(question: String, options: [String]? = nil, multiSelect: Bool? = nil) {
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// 一次未决的 AskUserQuestion 请求。Claude 把它通过 PermissionRequest hook 同步发来，
/// 用 `tool_name == "AskUserQuestion"` 判别；用户在气泡里填好答案后通过同一条挂起的 socket
/// 连接回写 `updatedInput.answers = { 问题: 答案 }`，让 Claude 把工具结果直接拿到。
public struct PendingAskUser: Codable, Sendable, Hashable {
    public let requestId: String
    public let questions: [AskUserQuestionItem]
    /// 原始 tool_input 的 JSON 序列化（按白名单提取后的子集）。
    /// 回写时需要解码出来，把 `answers` 合并进去再作为 updatedInput 返回，
    /// 否则 Claude 端可能因为缺字段判失败。用 Data 存是为了让 PendingAskUser
    /// 自己保持 Hashable（[String: AnyCodable] 不是 Hashable）。
    public let originalToolInputJSON: Data

    public init(requestId: String, questions: [AskUserQuestionItem], originalToolInputJSON: Data = Data()) {
        self.requestId = requestId
        self.questions = questions
        self.originalToolInputJSON = originalToolInputJSON
    }
}

/// 一个活跃的 AI CLI 会话。
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let tool: AITool
    public var cwd: String
    public var title: String?
    public var terminalApp: String?
    public var terminalTty: String?
    public var terminalSessionId: String?
    public let startedAt: Date
    public var currentState: PetState
    public var stateSince: Date
    /// 最近一次收到任何事件的时间戳；用于陈旧 session 清理（VS Code 插件等不发 session_end 的场景）。
    public var lastActivityAt: Date
    public var lastPromptSnippet: String?

    /// AskUserQuestion 当前的提问文案（PreToolUse 路径填，fire-and-forget，仅展示用）。
    /// 当 `pendingAskUser` 也存在时，气泡优先用结构化的 `pendingAskUser` 来渲染并允许直接作答。
    public var pendingQuestion: String?
    /// 结构化的 AskUserQuestion 待回答项（PermissionRequest 路径填，带 requestId 可同步回写答案）。
    public var pendingAskUser: PendingAskUser?
    /// PermissionRequest 当前的待决策项；用户在气泡上点 Allow/Deny 后清空。
    public var pendingPermission: PendingPermission?

    public init(
        id: String,
        tool: AITool,
        cwd: String,
        title: String? = nil,
        terminalApp: String? = nil,
        terminalTty: String? = nil,
        terminalSessionId: String? = nil,
        startedAt: Date = Date(),
        currentState: PetState = .idle,
        stateSince: Date = Date(),
        lastActivityAt: Date = Date(),
        lastPromptSnippet: String? = nil,
        pendingQuestion: String? = nil,
        pendingAskUser: PendingAskUser? = nil,
        pendingPermission: PendingPermission? = nil
    ) {
        self.id = id
        self.tool = tool
        self.cwd = cwd
        self.title = title
        self.terminalApp = terminalApp
        self.terminalTty = terminalTty
        self.terminalSessionId = terminalSessionId
        self.startedAt = startedAt
        self.currentState = currentState
        self.stateSince = stateSince
        self.lastActivityAt = lastActivityAt
        self.lastPromptSnippet = lastPromptSnippet
        self.pendingQuestion = pendingQuestion
        self.pendingAskUser = pendingAskUser
        self.pendingPermission = pendingPermission
    }

    /// cwd 最后一段路径组件，从 cwd 派生（cwd 改变后随之刷新）。
    public var cwdLastComponent: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// 气泡上展示的标题（最多 18 字符，无标题时回退到 cwd）。
    public var displayTitle: String {
        let raw = title ?? cwdLastComponent
        return String(raw.prefix(18))
    }

    /// 气泡上展示的耗时（实时由 stateSince 计算）。
    public func elapsedDescription(now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(stateSince)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
