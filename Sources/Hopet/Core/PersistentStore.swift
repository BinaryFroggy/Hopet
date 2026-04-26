import Foundation

/// 把 SessionRegistry 的快照写到 ~/.hopet/state/sessions.json。
/// 启动时恢复 10 分钟内的 session 为灰度 idle。
public enum PersistentStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func save(_ sessions: [Session]) {
        do {
            let data = try encoder.encode(sessions)
            try data.write(to: HopetPaths.sessionsState, options: .atomic)
        } catch {
            HopetLog.warn("save sessions failed: \(error)")
        }
    }

    public static func loadRecent() -> [Session] {
        guard let data = try? Data(contentsOf: HopetPaths.sessionsState), !data.isEmpty else { return [] }
        do {
            let all = try decoder.decode([Session].self, from: data)
            let cutoff = Date().addingTimeInterval(-600) // 10 分钟
            return all.filter { $0.stateSince >= cutoff }
                       .map { var s = $0; s.currentState = .idle; return s }
        } catch {
            HopetLog.warn("load sessions failed: \(error)")
            return []
        }
    }
}
