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

    /// 无 emoji 的状态文字（气泡 UI 用，色彩由独立的状态色圆点承担，不需要再夹带表情）。
    public var badgeLabel: String {
        switch self {
        case .idle:             return "Idle"
        case .responding:       return "Responding"
        case .thinking:         return "Thinking"
        case .toolUse:          return "Tool"
        case .permissionPrompt: return "Permission"
        case .askUser:          return "Ask"
        case .completed:        return "Done"
        case .errorInterrupted: return "Error"
        }
    }

    /// 状态对应的占位 glyph（OverviewTab / ThemePackage fallback 用）。
    public var glyph: String {
        switch self {
        case .idle:             return "💤"
        case .responding:       return "💬"
        case .thinking:         return "🌀"
        case .toolUse:          return "🛠"
        case .permissionPrompt: return "⚠️"
        case .askUser:          return "❓"
        case .completed:        return "✓"
        case .errorInterrupted: return "✗"
        }
    }

    /// v0.1 的占位文字徽章（无动画时直接显示这段文字代替海豹）。
    public var badgeText: String { "\(glyph) \(badgeLabel)" }

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
    /// 相对系统色降饱和约 30-40%，更接近 pastel 色调，与肥皂泡的轻盈视觉风格一致。
    public var accentColor: Color {
        switch self {
        case .idle:             return Color(white: 0.55)
        case .responding:       return Color(red: 0.46, green: 0.64, blue: 0.86) // soft blue
        case .thinking:         return Color(red: 0.62, green: 0.50, blue: 0.78) // soft purple
        case .toolUse:          return Color(red: 0.45, green: 0.74, blue: 0.74) // soft teal
        case .permissionPrompt: return Color(red: 0.84, green: 0.50, blue: 0.50) // soft red
        case .askUser:          return Color(red: 0.86, green: 0.76, blue: 0.45) // soft yellow
        case .completed:        return Color(red: 0.50, green: 0.74, blue: 0.55) // soft green
        case .errorInterrupted: return Color(white: 0.55)
        }
    }
}
