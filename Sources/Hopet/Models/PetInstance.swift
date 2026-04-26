import Foundation
import CoreGraphics

/// 一只宠物的渲染实例。1:1 绑定一个 AITool。
public struct PetInstance: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let tool: AITool
    public var themeId: String
    public var screenPosition: CGPoint
    public var visible: Bool
    public var aggregatedState: PetState
    public var drivenBySessionId: String?

    public init(
        id: UUID = UUID(),
        tool: AITool,
        themeId: String = "hopi.default",
        screenPosition: CGPoint = .zero,
        visible: Bool = true,
        aggregatedState: PetState = .idle,
        drivenBySessionId: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.themeId = themeId
        self.screenPosition = screenPosition
        self.visible = visible
        self.aggregatedState = aggregatedState
        self.drivenBySessionId = drivenBySessionId
    }
}
