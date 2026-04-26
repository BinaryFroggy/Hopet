import Foundation

/// completed → idle 的 2s 延迟降级，以及陈旧 session 清理（默认 10 分钟无事件）。
@MainActor
public final class CompletedDecayTimer {
    private unowned let registry: SessionRegistry
    private var timer: Timer?

    public init(registry: SessionRegistry) {
        self.registry = registry
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 陈旧阈值：超过这个时长没有任何事件视为僵尸 session。
    /// VS Code Claude 插件等场景不发 SessionEnd hook，会堆积，所以阈值不能过宽。
    private let staleThreshold: TimeInterval = 600  // 10 min

    private func tick() {
        let now = Date()
        for (id, session) in registry.sessions {
            // completed → idle 2s 后
            if session.currentState == .completed,
               now.timeIntervalSince(session.stateSince) >= 2 {
                registry.transition(sessionId: id, to: .idle, at: now)
            }

            // 长时间无事件 → 移除（基于 lastActivityAt，不再用 stateSince）。
            if now.timeIntervalSince(session.lastActivityAt) >= staleThreshold {
                registry.remove(id)
            }
        }
    }
}
