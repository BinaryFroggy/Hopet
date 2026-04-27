import Foundation

/// 围绕宠物环绕的会话气泡。1:1 绑定一个 sessionId。
public struct SessionBubble: Identifiable, Sendable {
    public let id: String
    public let tool: AITool
    public var orbitAngle: Double
    public var orbitRing: Int
    public var displayTitle: String
    /// 是否有用户/AI 写入的真实标题。`false` 时 displayTitle 是从 cwd 回退出来的占位，
    /// 视图应避免再单独渲染"标题"，否则会和目录行重复。
    public var hasTitle: Bool
    public var displayCwd: String
    public var displayElapsed: String
    public var state: PetState
    public var expanded: Bool
    public var pendingQuestion: String?
    public var pendingAskUser: PendingAskUser?
    public var pendingPermission: PendingPermission?

    public init(
        id: String,
        tool: AITool,
        orbitAngle: Double = 0,
        orbitRing: Int = 0,
        displayTitle: String,
        hasTitle: Bool = false,
        displayCwd: String,
        displayElapsed: String = "0s",
        state: PetState = .idle,
        expanded: Bool = false,
        pendingQuestion: String? = nil,
        pendingAskUser: PendingAskUser? = nil,
        pendingPermission: PendingPermission? = nil
    ) {
        self.id = id
        self.tool = tool
        self.orbitAngle = orbitAngle
        self.orbitRing = orbitRing
        self.displayTitle = displayTitle
        self.hasTitle = hasTitle
        self.displayCwd = displayCwd
        self.displayElapsed = displayElapsed
        self.state = state
        self.expanded = expanded
        self.pendingQuestion = pendingQuestion
        self.pendingAskUser = pendingAskUser
        self.pendingPermission = pendingPermission
    }
}
