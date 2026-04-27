import Foundation

/// 每 500ms 扫一次：把停留 ≥ 8s 的 responding 升级为 thinking（架构文档 §7.3）。
@MainActor
public final class ThinkingTimer {
    private unowned let registry: SessionRegistry
    private var timer: Timer?

    public init(registry: SessionRegistry) {
        self.registry = registry
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        for (_, session) in registry.sessions {
            guard session.currentState == .responding,
                  now.timeIntervalSince(session.stateSince) >= 8 else { continue }
            registry.transition(sessionId: session.id, to: .thinking, at: now)
        }
    }
}
