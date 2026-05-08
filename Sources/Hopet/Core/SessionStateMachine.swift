import Foundation

/// 单 session 状态转换函数（架构文档 §7.1 / §7.2）。
/// 纯函数，方便单测；不直接持有 Session。
public enum SessionStateMachine {
    /// 给定当前状态与事件，返回下一状态；返回 nil 表示「忽略该事件，状态不变」。
    public static func nextState(from current: PetState, event: EventKind) -> PetState? {
        switch (current, event) {
        case (_, .sessionStart):
            return .idle

        // user_prompt：从 idle / errorInterrupted / askUser 都可以进入 responding
        case (_, .userPrompt):
            return .responding

        // thinking_start：仅 responding 升级到 thinking
        case (.responding, .thinkingStart):
            return .thinking

        // pre_tool_use：responding / thinking → toolUse
        case (.responding, .preToolUse), (.thinking, .preToolUse), (.idle, .preToolUse):
            return .toolUse

        // post_tool_use：toolUse / permissionPrompt → responding
        case (.toolUse, .postToolUse),
             (.permissionPrompt, .postToolUse):
            return .responding

        // permission_ask：responding / thinking / toolUse / idle → permissionPrompt
        // idle 是为冷启动兜底：handleStateEvent 按需创建出的 idle session 第一条就是 permission_ask
        // （subagent reroute 到主 session 但主 session 还没 user_prompt 时也走这里），
        // 不切的话气泡展开但宠物动画停在 idle。
        case (.responding, .permissionAsk),
             (.thinking, .permissionAsk),
             (.toolUse, .permissionAsk),
             (.idle, .permissionAsk):
            return .permissionPrompt

        // ask_user：从任意主动状态进入 askUser
        case (.responding, .askUser),
             (.thinking, .askUser),
             (.toolUse, .askUser),
             (.idle, .askUser):
            return .askUser

        // ask_user_resolved：从 askUser 回到 responding
        case (.askUser, .askUserResolved):
            return .responding

        // .error 来自 PostToolUseFailure，覆盖 grep / head / ls 这类 exit-code-非-0 的常态情况，
        // 不再映射成 .errorInterrupted —— 否则用户每次正常会话里都会看到海豹变红。EventRouter
        // 仍会借 .error 调 cancelPending 清待决策气泡，但状态机不切。`.errorInterrupted` 保留为
        // 类型值，留给未来真正需要"会话级错误"语义的事件源（目前没有）。

        // stop：任意活跃状态进入 completed
        case (.responding, .stop),
             (.thinking, .stop),
             (.toolUse, .stop),
             (.permissionPrompt, .stop),
             (.askUser, .stop):
            return .completed

        case (.completed, .stop), (.idle, .stop), (.errorInterrupted, .stop):
            return nil

        default:
            return nil
        }
    }
}
