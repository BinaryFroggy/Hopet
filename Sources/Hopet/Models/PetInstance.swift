import Foundation
import CoreGraphics

/// 全局唯一的宠物渲染实例。状态由所有活跃 session 聚合得出，不再按 AI 工具分组。
public struct PetInstance: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var themeId: String
    public var screenPosition: CGPoint
    public var visible: Bool
    public var aggregatedState: PetState
    public var drivenBySessionId: String?

    public init(
        id: UUID = UUID(),
        themeId: String = "hopi.default",
        screenPosition: CGPoint = .zero,
        visible: Bool = true,
        aggregatedState: PetState = .idle,
        drivenBySessionId: String? = nil
    ) {
        self.id = id
        self.themeId = themeId
        self.screenPosition = screenPosition
        self.visible = visible
        self.aggregatedState = aggregatedState
        self.drivenBySessionId = drivenBySessionId
    }
}
