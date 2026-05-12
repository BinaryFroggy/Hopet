import Foundation

extension String {
    /// hopet 内部日志展示用：取前 8 字符作为短 id 前缀。
    var hopetShortId: String { String(prefix(8)) }
}

/// 一次未决的权限请求（Claude PermissionRequest hook 触发）。
/// requestId 是 hopet-emit 生成、Hopet 通过 socket 反向回写决策时必须带上的 token。
public struct PendingPermission: Codable, Sendable, Hashable {
    /// CC ExitPlanMode 工具名常量。气泡侧、enqueue 入口、外推尺寸 hint 都靠这个匹配，
    /// 写错就会静默走通用 allow/deny 卡片而非 plan-approval。
    public static let exitPlanModeTool = "ExitPlanMode"

    public let requestId: String
    public let toolName: String
    public let command: String?
    public let filePath: String?
    /// 仅 ExitPlanMode 时填，承载已 trim/截断的 plan markdown 正文。
    public let plan: String?

    public init(
        requestId: String,
        toolName: String,
        command: String? = nil,
        filePath: String? = nil,
        plan: String? = nil
    ) {
        self.requestId = requestId
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.plan = plan
    }

    public var isPlanApproval: Bool { toolName == Self.exitPlanModeTool }
}

/// AskUserQuestion 选项：`label` 是回写 answers 的规范值，`description` 是给用户看的副标题（可空）。
/// 协议层 answers map 的 value 始终是 label，description 仅用于渲染，不参与匹配。
public struct AskUserQuestionOption: Codable, Sendable, Hashable {
    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

/// AskUserQuestion (elicitation) 的单个问题项。
public struct AskUserQuestionItem: Codable, Sendable, Hashable {
    public let question: String
    public let options: [AskUserQuestionOption]?
    public let multiSelect: Bool?

    public init(question: String, options: [AskUserQuestionOption]? = nil, multiSelect: Bool? = nil) {
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

/// 一条 session 当前承载的"等待用户"卡片类型。
/// 决定气泡高度估算与 scrollToFocus 的等价比较口径——permission 与 planApproval
/// 单独分项，因为两者展开高度差近 200pt，不能折叠成同一类。
public enum SessionPendingKind: String, Hashable, Sendable {
    case permission = "P"
    case planApproval = "PL"
    case askUser = "A"
    case legacyQuestion = "Q"
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
    /// 上一轮 Claude 完成回复时（Stop hook）写入的回复开头，已截断到 120 字符。
    /// 默认气泡第二行渲染用。在 UserPromptSubmit（开始新一轮）时清空，避免把上一轮尾声
    /// 串到新一轮的"思考中"语境里。
    public var lastAssistantMessage: String?

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
        lastAssistantMessage: String? = nil,
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
        self.lastAssistantMessage = lastAssistantMessage
        self.pendingQuestion = pendingQuestion
        self.pendingAskUser = pendingAskUser
        self.pendingPermission = pendingPermission
    }

    /// cwd 最后一段路径组件，从 cwd 派生（cwd 改变后随之刷新）。
    public var cwdLastComponent: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// 当前 pending 类型，按 PetStageView 的优先级（permission > askUser > legacyQuestion）展开。
    /// 顺序与 SessionBubbleView 的卡片选择保持一致。
    public var pendingKind: SessionPendingKind? {
        if let pp = pendingPermission { return pp.isPlanApproval ? .planApproval : .permission }
        if pendingAskUser != nil { return .askUser }
        if pendingQuestion != nil { return .legacyQuestion }
        return nil
    }

    /// 气泡上展示的标题（最多 40 字符，无标题时回退到 cwd）。
    /// 视图层根据 `hasUserTitle`/`SessionBubble.hasTitle` 决定是否实际渲染该字段，
    /// 避免在没有真实标题时和目录名重复显示。
    public var displayTitle: String {
        let raw = title ?? cwdLastComponent
        return String(raw.prefix(40))
    }

    /// 气泡上展示的耗时（实时由 stateSince 计算）。
    public func elapsedDescription(now: Date = Date()) -> String {
        Self.humanDuration(max(0, Int(now.timeIntervalSince(stateSince))))
    }

    /// 上一个状态持续了多久 / 距完成多久。
    /// - 运行中：返回 "running 5m"
    /// - 闲置/已完成/错误：返回 "5m ago"
    public func stateDurationPhrase(now: Date = Date()) -> String {
        let unit = elapsedDescription(now: now)
        return currentState.isRunning ? "running \(unit)" : "\(unit) ago"
    }

    private static func humanDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
