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

    /// 是否处于"用户/工具正在驱动"的进行态。idle / completed / errorInterrupted 是终态/静态。
    /// 用作 EventRouter 自动清扫躺尸 session 的判据、Session.stateDurationPhrase 的措辞分支、
    /// 折叠态气泡时间前缀图标的开关，三处共用一个事实之源。
    public var isRunning: Bool {
        switch self {
        case .thinking, .responding, .toolUse, .askUser, .permissionPrompt: return true
        case .idle, .completed, .errorInterrupted: return false
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
    /// 8-bit 像素风：饱和度拉到接近原色，让小气泡左上角的状态方块、permission shield、按钮 tint
    /// 在白底像素外壳上能"跳"出来。idle / errorInterrupted 仍走中性灰，避免抢戏。
    public var accentColor: Color {
        switch self {
        case .idle:             return Color(white: 0.55)
        case .responding:       return Color(red: 0.18, green: 0.55, blue: 0.98) // vivid blue
        case .thinking:         return Color(red: 0.62, green: 0.30, blue: 0.94) // vivid purple
        case .toolUse:          return Color(red: 0.10, green: 0.78, blue: 0.78) // vivid teal
        case .permissionPrompt: return Color(red: 0.97, green: 0.28, blue: 0.32) // vivid red
        case .askUser:          return Color(red: 0.99, green: 0.78, blue: 0.10) // vivid yellow
        case .completed:        return Color(red: 0.20, green: 0.82, blue: 0.42) // vivid green
        case .errorInterrupted: return Color(white: 0.55)
        }
    }
}
