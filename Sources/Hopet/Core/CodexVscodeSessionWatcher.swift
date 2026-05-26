import Foundation

/// Bridges Codex VSCode/Cursor local rollout files into Hopet's normal event router.
///
/// The VSCode plugin does not invoke `~/.codex/hooks.json`; it appends a JSONL
/// rollout under `~/.codex/sessions`. Watching that file gives Hopet the same
/// non-blocking lifecycle states as Codex CLI hooks, while permission decisions
/// remain owned by the plugin UI.
@MainActor
final class CodexVscodeSessionWatcher {
    private static let pollInterval: TimeInterval = 0.8
    private static let discoveryInterval: TimeInterval = 5
    private static let discoveryLookback: TimeInterval = 60 * 60
    private static let activeResumeWindow: TimeInterval = 10 * 60
    private static let trackedFileRetainWindow: TimeInterval = 24 * 60 * 60
    private static let initialHeadScanBytes: UInt64 = 1024 * 1024
    private static let initialTailScanBytes: UInt64 = 4 * 1024 * 1024

    private let router: EventRouter
    private let fileManager: FileManager
    private let sessionsDirectory: URL
    private var timer: Timer?
    private var lastDiscoveryAt: Date = .distantPast
    private var cursors: [String: Cursor] = [:]

    init(
        router: EventRouter,
        fileManager: FileManager = .default,
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    ) {
        self.router = router
        self.fileManager = fileManager
        self.sessionsDirectory = sessionsDirectory
    }

    func start() {
        guard timer == nil else { return }
        discoverRollouts(force: true)
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        HopetLog.trace("codex-vscode", "watcher started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cursors.removeAll()
        HopetLog.trace("codex-vscode", "watcher stopped")
    }

    private func poll() {
        discoverRollouts(force: false)
        for path in cursors.keys.sorted() {
            processRollout(at: path)
        }
    }

    private func discoverRollouts(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastDiscoveryAt) >= Self.discoveryInterval else { return }
        lastDiscoveryAt = now

        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        let cutoff = now.addingTimeInterval(-Self.discoveryLookback)
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-") else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff else { continue }
            if cursors[url.path] == nil {
                cursors[url.path] = Cursor(path: url.path)
            }
        }

        let staleCutoff = now.addingTimeInterval(-Self.trackedFileRetainWindow)
        let stalePaths = cursors.compactMap { path, cursor -> String? in
            guard cursor.currentTurnId == nil else { return nil }
            let modifiedAt = modificationDate(forPath: path) ?? .distantPast
            return modifiedAt < staleCutoff ? path : nil
        }
        for path in stalePaths {
            cursors.removeValue(forKey: path)
        }
    }

    private func processRollout(at path: String) {
        let url = URL(fileURLWithPath: path)
        guard let size = fileSize(forPath: path) else {
            cursors.removeValue(forKey: path)
            return
        }
        guard var cursor = cursors[path] else { return }

        if !cursor.didInitialize {
            initialize(&cursor, from: url, fileSize: size)
            cursors[path] = cursor
            return
        }

        if size < cursor.offset {
            cursor = Cursor(path: path)
            initialize(&cursor, from: url, fileSize: size)
            cursors[path] = cursor
            return
        }

        guard size > cursor.offset else {
            cursors[path] = cursor
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: cursor.offset)
            let data = handle.readDataToEndOfFile()
            cursor.offset += UInt64(data.count)
            process(data: data, cursor: &cursor, mode: .live)
            cursors[path] = cursor
        } catch {
            HopetLog.trace("codex-vscode", "read failed path=\(url.lastPathComponent) error=\(error)")
        }
    }

    private func initialize(_ cursor: inout Cursor, from url: URL, fileSize: UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        cursor.didInitialize = true
        cursor.offset = fileSize

        do {
            let headCount = min(fileSize, Self.initialHeadScanBytes)
            if headCount > 0 {
                let head = handle.readData(ofLength: Int(headCount))
                process(data: head, cursor: &cursor, mode: .scan)
            }

            if fileSize > headCount {
                let tailStart = max(headCount, fileSize - min(fileSize, Self.initialTailScanBytes))
                cursor.partialLine = ""
                try handle.seek(toOffset: tailStart)
                let tail = handle.readDataToEndOfFile()
                process(data: tail, cursor: &cursor, mode: .scan)
            }

            synthesizeActiveStateIfNeeded(cursor: &cursor)
        } catch {
            HopetLog.trace("codex-vscode", "initial scan failed path=\(url.lastPathComponent) error=\(error)")
        }
    }

    private func process(data: Data, cursor: inout Cursor, mode: ProcessingMode) {
        guard !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        for line in completeLines(from: text, carrying: &cursor.partialLine) {
            guard let record = decode(line) else { continue }
            apply(record, cursor: &cursor, mode: mode)
        }
    }

    private func completeLines(from text: String, carrying partialLine: inout String) -> [String] {
        let combined = partialLine + text
        var parts = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if combined.hasSuffix("\n") {
            partialLine = ""
        } else {
            partialLine = parts.popLast() ?? ""
        }
        return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func decode(_ line: String) -> RolloutRecord? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? Self.decoder.decode(RolloutRecord.self, from: data)
    }

    private func apply(_ record: RolloutRecord, cursor: inout Cursor, mode: ProcessingMode) {
        let timestamp = parseTimestamp(record.timestamp) ?? Date()
        guard let payload = record.payload else { return }
        if record.type == "session_meta" {
            applySessionMeta(payload, cursor: &cursor)
            return
        }
        guard let payloadType = payload.string("type") else { return }

        guard cursor.metadata.isEligible else { return }
        cursor.lastEventAt = timestamp

        switch payloadType {
        case "task_started":
            cursor.currentTurnId = payload.string("turn_id") ?? UUID().uuidString
            cursor.activeToolCalls.removeAll()
            cursor.latestToolName = nil
            cursor.lastUserMessage = nil
            cursor.lastAgentMessage = nil
            if mode == .live {
                ensureSessionStarted(cursor: &cursor, at: timestamp)
                emit(.userPrompt, cursor: cursor, timestamp: timestamp, extraPayload: [
                    "prompt": AnyCodable("Codex VSCode turn")
                ])
            }

        case "user_message":
            guard let message = payload.string("message") else { return }
            cursor.lastUserMessage = message
            markTurnActiveIfNeeded(cursor: &cursor, at: timestamp)
            if mode == .live, cursor.currentTurnId != nil {
                ensureSessionStarted(cursor: &cursor, at: timestamp)
                emit(.userPrompt, cursor: cursor, timestamp: timestamp, extraPayload: [
                    "prompt": AnyCodable(message)
                ])
            }

        case "agent_message":
            if let message = payload.string("message") {
                cursor.lastAgentMessage = message
            }
            if mode == .scan {
                markTurnActiveIfNeeded(cursor: &cursor, at: timestamp)
            }

        case "function_call", "custom_tool_call":
            let callId = payload.string("call_id") ?? UUID().uuidString
            let name = payload.string("name") ?? payloadType
            markTurnActiveIfNeeded(cursor: &cursor, at: timestamp)
            cursor.activeToolCalls.insert(callId)
            cursor.latestToolName = name
            if mode == .live {
                ensureSessionStarted(cursor: &cursor, at: timestamp)
                emit(.preToolUse, cursor: cursor, timestamp: timestamp, extraPayload: toolPayload(
                    name: name,
                    callId: callId,
                    arguments: payload.string("arguments")
                ))
            }

        case "function_call_output", "custom_tool_call_output":
            let callId = payload.string("call_id")
            let hadActiveToolCalls = !cursor.activeToolCalls.isEmpty
            if let callId {
                cursor.activeToolCalls.remove(callId)
            } else {
                cursor.activeToolCalls.removeAll()
            }
            if mode == .live, cursor.didEmitSessionStart, hadActiveToolCalls, cursor.activeToolCalls.isEmpty {
                emit(.postToolUse, cursor: cursor, timestamp: timestamp, extraPayload: [
                    "tool_use_id": AnyCodable(callId ?? "")
                ])
            }

        case "task_complete":
            if let message = payload.string("last_agent_message") {
                cursor.lastAgentMessage = message
            }
            cursor.currentTurnId = nil
            cursor.activeToolCalls.removeAll()
            cursor.latestToolName = nil
            if mode == .live {
                ensureSessionStarted(cursor: &cursor, at: timestamp)
                emit(.stop, cursor: cursor, timestamp: timestamp, extraPayload: [
                    "assistant_message": AnyCodable(cursor.lastAgentMessage ?? "")
                ])
            }

        case "turn_aborted":
            cursor.currentTurnId = nil
            cursor.activeToolCalls.removeAll()
            cursor.latestToolName = nil
            if mode == .live, cursor.didEmitSessionStart {
                emit(.stop, cursor: cursor, timestamp: timestamp, extraPayload: [
                    "assistant_message": AnyCodable("Turn aborted")
                ])
            }

        default:
            break
        }
    }

    private func markTurnActiveIfNeeded(cursor: inout Cursor, at timestamp: Date) {
        guard cursor.currentTurnId == nil else { return }
        let millis = Int(timestamp.timeIntervalSince1970 * 1000)
        cursor.currentTurnId = "implicit-\(millis)"
    }

    private func applySessionMeta(_ payload: [String: AnyCodable], cursor: inout Cursor) {
        guard let threadId = payload.string("id"), !threadId.isEmpty else {
            cursor.metadata.isEligible = false
            return
        }
        if payload.string("thread_source") == "subagent" {
            cursor.metadata.isEligible = false
            return
        }

        let originator = payload.string("originator")
        let source = payload.string("source")
        guard originator == "codex_vscode" || source == "vscode" else {
            cursor.metadata.isEligible = false
            return
        }

        cursor.metadata.threadId = threadId
        cursor.metadata.cwd = payload.string("cwd")
        cursor.metadata.isEligible = true
        if !cursor.metadata.didLogEligibility {
            cursor.metadata.didLogEligibility = true
            HopetLog.trace(
                "codex-vscode",
                "watch sid=\(cursor.metadata.sessionId?.hopetShortId ?? threadId.hopetShortId) cwd=\(cursor.metadata.cwd ?? "-")"
            )
        }
    }

    private func synthesizeActiveStateIfNeeded(cursor: inout Cursor) {
        guard cursor.metadata.isEligible,
              cursor.currentTurnId != nil,
              let lastEventAt = cursor.lastEventAt,
              Date().timeIntervalSince(lastEventAt) <= Self.activeResumeWindow else { return }

        ensureSessionStarted(cursor: &cursor, at: lastEventAt)
        emit(.userPrompt, cursor: cursor, timestamp: lastEventAt, extraPayload: [
            "prompt": AnyCodable(cursor.lastUserMessage ?? "Codex VSCode turn")
        ])
        if !cursor.activeToolCalls.isEmpty, let latestToolName = cursor.latestToolName {
            emit(.preToolUse, cursor: cursor, timestamp: lastEventAt, extraPayload: toolPayload(
                name: latestToolName,
                callId: cursor.activeToolCalls.sorted().last ?? "",
                arguments: nil
            ))
        }
    }

    private func ensureSessionStarted(cursor: inout Cursor, at timestamp: Date) {
        guard !cursor.didEmitSessionStart else { return }
        cursor.didEmitSessionStart = true
        emit(.sessionStart, cursor: cursor, timestamp: timestamp, extraPayload: [:])
    }

    private func emit(
        _ kind: EventKind,
        cursor: Cursor,
        timestamp: Date,
        extraPayload: [String: AnyCodable]
    ) {
        guard let sessionId = cursor.metadata.sessionId else { return }
        var payload: [String: AnyCodable] = [
            "origin": AnyCodable("codex_vscode"),
            "transcript_path": AnyCodable(cursor.path)
        ]
        if let threadId = cursor.metadata.threadId {
            payload["thread_id"] = AnyCodable(threadId)
        }
        if let turnId = cursor.currentTurnId {
            payload["turn_id"] = AnyCodable(turnId)
        }
        for (key, value) in extraPayload {
            payload[key] = value
        }

        let event = StateEvent(
            sessionId: sessionId,
            tool: .codex,
            event: kind,
            timestamp: timestamp,
            cwd: cursor.metadata.cwd,
            terminalApp: "Codex VSCode",
            terminalSessionId: cursor.metadata.threadId,
            payload: payload
        )
        router.handle(event)
    }

    private func toolPayload(name: String, callId: String, arguments: String?) -> [String: AnyCodable] {
        var payload: [String: AnyCodable] = [
            "tool_name": AnyCodable(name),
            "tool_use_id": AnyCodable(callId)
        ]
        if let arguments {
            payload["arguments"] = AnyCodable(arguments)
        }
        return payload
    }

    private func fileSize(forPath path: String) -> UInt64? {
        guard let size = (try? fileManager.attributesOfItem(atPath: path)[.size]) as? NSNumber else {
            return nil
        }
        return size.uint64Value
    }

    private func modificationDate(forPath path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    private func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return Self.fractionalDateFormatter.date(from: value) ?? Self.dateFormatter.date(from: value)
    }

    private static let decoder = JSONDecoder()

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum ProcessingMode {
    case scan
    case live
}

private struct RolloutRecord: Decodable {
    let timestamp: String?
    let type: String
    let payload: [String: AnyCodable]?
}

private struct Cursor {
    let path: String
    var didInitialize = false
    var offset: UInt64 = 0
    var partialLine = ""
    var metadata = RolloutMetadata()
    var didEmitSessionStart = false
    var currentTurnId: String?
    var activeToolCalls: Set<String> = []
    var latestToolName: String?
    var lastUserMessage: String?
    var lastAgentMessage: String?
    var lastEventAt: Date?
}

private struct RolloutMetadata {
    var isEligible = false
    var didLogEligibility = false
    var threadId: String?
    var cwd: String?

    var sessionId: String? {
        guard let threadId, !threadId.isEmpty else { return nil }
        return "codex-vscode-\(threadId)"
    }
}

private extension Dictionary where Key == String, Value == AnyCodable {
    func string(_ key: String) -> String? {
        self[key]?.value as? String
    }
}
