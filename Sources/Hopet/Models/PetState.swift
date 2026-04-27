import Foundation
import SwiftUI

/// 单个 session 或聚合后的宠物状态。rawValue 与 manifest.json 中 animation key 一一对应。
public enum PetState: String, Codable, CaseIterable, Hashable, Sendable {
    case idle
    case thinking
    case responding
    case toolUse          = "tool-use"
    case permissionPrompt = "permission-prompt"
    case askUser          = "ask-user"
    case completed
    case errorInterrupted = "error-interrupted"

    /// 优先级数字。越小越优先（详见 hooks-and-priority.md §2）。
    public var priority: Int {
        switch self {
        case .askUser:          return 0
        case .permissionPrompt: return 1
        case .errorInterrupted: return 2
        case .toolUse:          return 3
        case .thinking:         return 4
        case .responding:       return 5
        case .completed:        return 6
        case .idle:             return 7
        }
    }

    /// v0.1 的占位文字徽章（无动画时直接显示这段文字代替海豹）。
    public var badgeText: String {
        switch self {
        case .idle:             return "💤 Idle"
        case .responding:       return "💬 Responding"
        case .thinking:         return "🌀 Thinking"
        case .toolUse:          return "🛠 Tool"
        case .permissionPrompt: return "⚠️ Permission"
        case .askUser:          return "❓ Ask"
        case .completed:        return "✓ Done"
        case .errorInterrupted: return "✗ Error"
        }
    }

    /// 刘海条文案（feature.md §3.1）。
    public var notchCaption: String {
        switch self {
        case .idle:             return "Idle"
        case .responding:       return "正在回复…"
        case .thinking:         return "深度思考中…"
        case .toolUse:          return "执行工具…"
        case .permissionPrompt: return "⚠️ 需要权限确认"
        case .askUser:          return "❓ 在等你回答"
        case .completed:        return "完成 ✓"
        case .errorInterrupted: return "已中断"
        }
    }

    /// 状态色（features.md §3.1 颜色映射）。
    public var accentColor: Color {
        switch self {
        case .idle:             return Color(white: 0.55)
        case .responding:       return .blue
        case .thinking:         return .purple
        case .toolUse:          return .teal
        case .permissionPrompt: return .red
        case .askUser:          return .yellow
        case .completed:        return .green
        case .errorInterrupted: return .gray
        }
    }
}
