import Foundation

/// 围绕宠物环绕的会话气泡。1:1 绑定一个 sessionId。
public struct SessionBubble: Identifiable, Sendable {
    public let id: String
    public let tool: AITool
    public var orbitAngle: Double
    public var orbitRing: Int
    public var displayTitle: String
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
        self.displayCwd = displayCwd
        self.displayElapsed = displayElapsed
        self.state = state
        self.expanded = expanded
        self.pendingQuestion = pendingQuestion
        self.pendingAskUser = pendingAskUser
        self.pendingPermission = pendingPermission
    }
}
