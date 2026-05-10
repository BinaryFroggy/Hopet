import Combine
import Foundation

/// 偏好的运行时容器：持有 `HopetConfig` 当前值，写入即自动落盘。
/// See preferences.md §6.2.
@MainActor
public final class ConfigStore: ObservableObject {
    @Published public private(set) var current: HopetConfig

    public init(initial: HopetConfig = .load()) {
        self.current = initial
    }

    /// 用闭包修改 config 并落盘；值无变化时跳过。落盘失败不回滚内存值
    /// （AGENTS.md §2.3：错误处理仅在系统边界）。
    public func update(_ mutate: (inout HopetConfig) -> Void) {
        var next = current
        mutate(&next)
        guard next != current else { return }
        current = next
        next.save()
    }
}
