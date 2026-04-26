import Foundation

/// 把 Hopet 的 hook 注册项 merge 到用户 `~/.claude/settings.json` 与 `~/.codex/config.toml`。
public final class HookInstaller {
    public init() {}

    private var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private var codexConfig: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    }

    private var emitPath: String {
        HopetPaths.emitBinary.path
    }

    // MARK: - Public

    public func isInstalled(_ tool: AITool) -> Bool {
        switch tool {
        case .claudeCode:
            guard let json = try? readClaudeSettings() else { return false }
            guard let hooks = json["hooks"] as? [String: Any] else { return false }
            return containsHopetMarker(in: hooks)
        case .codex:
            guard let text = try? String(contentsOf: codexConfig) else { return false }
            return text.contains(HookScriptTemplates.hopetMarker)
        case .custom:
            return false
        }
    }

    @discardableResult
    public func install(_ tool: AITool) throws -> URL {
        try ensureEmitBinary()
        switch tool {
        case .claudeCode: return try installClaude()
        case .codex:      return try installCodex()
        case .custom:     throw NSError(domain: "Hopet.Hook", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "custom tool not supported in v0.1"])
        }
    }

    @discardableResult
    public func uninstall(_ tool: AITool) throws -> URL {
        switch tool {
        case .claudeCode: return try uninstallClaude()
        case .codex:      return try uninstallCodex()
        case .custom:     return codexConfig
        }
    }

    // MARK: - Claude

    private func installClaude() throws -> URL {
        try FileManager.default.createDirectory(at: claudeSettings.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var json = (try? readClaudeSettings()) ?? [:]
        try backup(claudeSettings)

        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let hopetEntries = HookScriptTemplates.claudeHooks(emitPath: emitPath)

        for (key, hopetItems) in hopetEntries {
            var existing = (hooks[key] as? [Any]) ?? []
            // 移除原先 Hopet 写过的同 key 条目，避免重复 append。
            existing = existing.filter { !isHopetEntry($0) }
            existing.append(contentsOf: hopetItems)
            hooks[key] = existing
        }
        json["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeSettings, options: .atomic)
        return claudeSettings
    }

    private func uninstallClaude() throws -> URL {
        guard var json = try? readClaudeSettings(),
              var hooks = json["hooks"] as? [String: Any] else {
            return claudeSettings
        }
        try backup(claudeSettings)
        for (key, value) in hooks {
            guard let arr = value as? [Any] else { continue }
            let filtered = arr.filter { !isHopetEntry($0) }
            if filtered.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = filtered
            }
        }
        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeSettings, options: .atomic)
        return claudeSettings
    }

    private func readClaudeSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: claudeSettings), !data.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private func containsHopetMarker(in hooks: [String: Any]) -> Bool {
        for (_, value) in hooks {
            guard let arr = value as? [Any] else { continue }
            if arr.contains(where: isHopetEntry) { return true }
        }
        return false
    }

    private func isHopetEntry(_ any: Any) -> Bool {
        guard let dict = any as? [String: Any],
              let inner = dict["hooks"] as? [Any] else { return false }
        return inner.contains { item in
            guard let one = item as? [String: Any],
                  let cmd = one["command"] as? String else { return false }
            return cmd.contains(HookScriptTemplates.hopetMarker)
        }
    }

    // MARK: - Codex

    private func installCodex() throws -> URL {
        try FileManager.default.createDirectory(at: codexConfig.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try backup(codexConfig)

        let args = HookScriptTemplates.codexNotifyArguments(emitPath: emitPath)
        let arrayLit = "[" + args.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        let block = """
        # >>> hopet-managed >>>
        [notify]
        command = \(arrayLit)
        # <<< hopet-managed <<<
        """

        var existing = (try? String(contentsOf: codexConfig)) ?? ""
        existing = stripHopetBlock(existing)
        if !existing.hasSuffix("\n") && !existing.isEmpty { existing += "\n" }
        existing += block + "\n"
        try existing.write(to: codexConfig, atomically: true, encoding: .utf8)
        return codexConfig
    }

    private func uninstallCodex() throws -> URL {
        guard var existing = try? String(contentsOf: codexConfig) else { return codexConfig }
        try backup(codexConfig)
        existing = stripHopetBlock(existing)
        try existing.write(to: codexConfig, atomically: true, encoding: .utf8)
        return codexConfig
    }

    private func stripHopetBlock(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var inside = false
        for line in lines {
            if line.contains("# >>> hopet-managed >>>") { inside = true; continue }
            if line.contains("# <<< hopet-managed <<<") { inside = false; continue }
            if !inside { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Common

    public func ensureEmitBinary() throws {
        try HopetPaths.ensureDirectories()
        let dst = HopetPaths.emitBinary
        let fm = FileManager.default

        var candidates: [URL] = []

        // 1. swift run 场景：与 Hopet 可执行文件同目录（最稳的来源）。
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("hopet-emit"))
        }
        // 2. 标准 .app bundle 场景。
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("hopet-emit"))
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hopet-emit"))
        // 3. 当前工作目录下 SPM 默认输出位置（dev 直跑兜底）。
        let cwd = fm.currentDirectoryPath
        for arch in ["arm64-apple-macosx", "x86_64-apple-macosx"] {
            for cfg in ["debug", "release"] {
                candidates.append(URL(fileURLWithPath: "\(cwd)/.build/\(arch)/\(cfg)/hopet-emit"))
            }
        }

        guard let src = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            let listing = candidates.map { "  - \($0.path)" }.joined(separator: "\n")
            HopetLog.warn("hopet-emit binary not found.\n\(listing)")
            HopetLog.trace("hopet-emit not found. Looked in:\n\(listing)")
            return
        }

        try? fm.removeItem(at: dst)
        try fm.copyItem(at: src, to: dst)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
        HopetLog.info("hopet-emit installed: \(src.path) → \(dst.path)")
        HopetLog.trace("hopet-emit installed at \(dst.path)")
    }

    private static let backupFormatter = ISO8601DateFormatter()

    private func backup(_ url: URL) throws {
        let stamp = Self.backupFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dst = url.deletingPathExtension().path + ".hopet.\(stamp).bak"
        try? FileManager.default.copyItem(atPath: url.path, toPath: dst)
    }
}
