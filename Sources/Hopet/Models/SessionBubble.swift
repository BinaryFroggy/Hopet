import Foundation

/// 列入会话气泡列表的一个会话视图模型。1:1 绑定一个 sessionId。
public struct SessionBubble: Identifiable, Sendable {
    public let id: String
    public let tool: AITool
    public var displayTitle: String
    /// 是否有用户/AI 写入的真实标题。`false` 时 displayTitle 是从 cwd 回退出来的占位，
    /// 视图应避免再单独渲染"标题"，否则会和目录行重复。
    public var hasTitle: Bool
    public var displayCwd: String
    public var state: PetState
    /// Stop hook 抽到的最近一次 Claude 回复开头（已 ≤120 字符）。默认卡片第二行渲染用；nil 时不渲染。
    public var lastAssistantMessage: String?
    public var pendingQuestion: String?
    public var pendingAskUser: PendingAskUser?
    public var pendingPermission: PendingPermission?

    public init(
        id: String,
        tool: AITool,
        displayTitle: String,
        hasTitle: Bool = false,
        displayCwd: String,
        state: PetState = .idle,
        lastAssistantMessage: String? = nil,
        pendingQuestion: String? = nil,
        pendingAskUser: PendingAskUser? = nil,
        pendingPermission: PendingPermission? = nil
    ) {
        self.id = id
        self.tool = tool
        self.displayTitle = displayTitle
        self.hasTitle = hasTitle
        self.displayCwd = displayCwd
        self.state = state
        self.lastAssistantMessage = lastAssistantMessage
        self.pendingQuestion = pendingQuestion
        self.pendingAskUser = pendingAskUser
        self.pendingPermission = pendingPermission
    }
}
