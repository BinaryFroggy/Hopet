import Foundation

/// 把 Hopet 的 hook 注册项 merge 到用户 `~/.claude/settings.json`、`~/.codex/hooks.json`
/// 与 `~/.hope-agent/config.json`（hope-agent 的 hooks 与 Claude 同构，落在 `hooks` 字段）。
public final class HookInstaller {
    public init() {}

    private var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private var codexHooksFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
    }

    /// Hope Agent 的主配置文件；hooks 落在它的 `hooks` 字段（结构与 Claude 同构）。
    /// 它同时承载 hope-agent 自己的 providers / 偏好等，所以 merge 必须只动 `hooks`、
    /// 保留其余字段；且**仅在文件已存在时**才写——hope-agent 没装就跳过，绝不创建一份
    /// 只有 hooks 的残缺 config。
    private var hopeAgentConfig: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hope-agent/config.json")
    }

    /// 仅在 install/uninstall 时用于清理历史 `[notify]` 块；不再作为事件源。
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
            guard let json = try? readCodexHooks(),
                  let hooks = json["hooks"] as? [String: Any] else { return false }
            return containsHopetMarker(in: hooks)
        case .hopeAgent:
            // 文件不存在 → readHopeAgentConfig 返回 [:]，hooks 取不到 → 未安装。
            guard let json = try? readHopeAgentConfig(),
                  let hooks = json["hooks"] as? [String: Any] else { return false }
            return containsHopetMarker(in: hooks)
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
        case .hopeAgent:  return try installHopeAgent()
        case .custom:     throw NSError(domain: "Hopet.Hook", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "custom tool not supported in v0.1"])
        }
    }

    @discardableResult
    public func uninstall(_ tool: AITool) throws -> URL {
        switch tool {
        case .claudeCode: return try uninstallClaude()
        case .codex:      return try uninstallCodex()
        case .hopeAgent:  return try uninstallHopeAgent()
        case .custom:     return codexHooksFile
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
    //
    // Codex CLI 0.129.0+ 用 `~/.codex/hooks.json` 注册生命周期 hook（需 features.codex_hooks）。
    // 安装时顺手清掉 config.toml 里 v0.1 留下的 [notify] 块，避免 stop 事件双发触发两次
    // completed 切换。See DevDocs/hooks-and-priority.md.

    private func installCodex() throws -> URL {
        try FileManager.default.createDirectory(at: codexHooksFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var json = (try? readCodexHooks()) ?? [:]
        try backup(codexHooksFile)

        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let hopetEntries = HookScriptTemplates.codexHooks(emitPath: emitPath)

        for (key, hopetItems) in hopetEntries {
            var existing = (hooks[key] as? [Any]) ?? []
            existing = existing.filter { !isHopetEntry($0) }
            existing.append(contentsOf: hopetItems)
            hooks[key] = existing
        }
        json["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: codexHooksFile, options: .atomic)

        // 迁移：剔除 v0.1 在 config.toml 中写的 [notify] 块。
        stripLegacyCodexNotify()

        return codexHooksFile
    }

    private func uninstallCodex() throws -> URL {
        // 同时清 hooks.json 中 Hopet 条目与 config.toml 历史 notify 块——卸载语义是
        // "把 Hopet 之前留下的 codex 接入全部撤掉"，两条路径都要兜底。
        stripLegacyCodexNotify()

        guard var json = try? readCodexHooks(),
              var hooks = json["hooks"] as? [String: Any] else {
            return codexHooksFile
        }
        try backup(codexHooksFile)
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
        if json.isEmpty {
            // 整个 hooks.json 只剩 Hopet 时直接删除文件，避免留空对象。
            try? FileManager.default.removeItem(at: codexHooksFile)
        } else {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: codexHooksFile, options: .atomic)
        }
        return codexHooksFile
    }

    private func readCodexHooks() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: codexHooksFile), !data.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    /// 清掉 `~/.codex/config.toml` 中 hopet 历史注入的 `[notify]` 块。文件本身不一定
    /// 存在（v0.1 没装过 Hopet 的用户），不存在就静默跳过。
    private func stripLegacyCodexNotify() {
        guard let existing = try? String(contentsOf: codexConfig) else { return }
        guard existing.contains(HookScriptTemplates.codexNotifyBlockBegin) else { return }
        try? backup(codexConfig)
        let stripped = stripHopetBlock(existing)
        try? stripped.write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    private func stripHopetBlock(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var inside = false
        for line in lines {
            if line.contains(HookScriptTemplates.codexNotifyBlockBegin) { inside = true; continue }
            if line.contains(HookScriptTemplates.codexNotifyBlockEnd) { inside = false; continue }
            if !inside { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Hope Agent
    //
    // hope-agent 的 hooks 与 Claude 同构，落在 `~/.hope-agent/config.json` 的 `hooks`
    // 字段。差别只有两点：(1) config.json 还承载 hope-agent 自己的 providers / 偏好，
    // 故只动 `hooks`、保留其余字段，且卸载清空后也绝不删整个文件；(2) 仅当文件已存在
    // （即 hope-agent 已安装）时才写——不存在就跳过，不创建残缺 config。

    private func installHopeAgent() throws -> URL {
        // hope-agent 未安装（config.json 不存在）→ no-op。首启自动安装会对所有 recognized
        // 工具调 install()，这里静默跳过不影响其它工具。
        guard FileManager.default.fileExists(atPath: hopeAgentConfig.path) else {
            HopetLog.info("hope-agent config not found, skip hook install: \(hopeAgentConfig.path)")
            return hopeAgentConfig
        }
        var json = (try? readHopeAgentConfig()) ?? [:]
        try backup(hopeAgentConfig)

        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let hopetEntries = HookScriptTemplates.hopeAgentHooks(emitPath: emitPath)
        for (key, hopetItems) in hopetEntries {
            var existing = (hooks[key] as? [Any]) ?? []
            existing = existing.filter { !isHopetEntry($0) }
            existing.append(contentsOf: hopetItems)
            hooks[key] = existing
        }
        json["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hopeAgentConfig, options: .atomic)
        return hopeAgentConfig
    }

    private func uninstallHopeAgent() throws -> URL {
        guard var json = try? readHopeAgentConfig(),
              var hooks = json["hooks"] as? [String: Any] else {
            return hopeAgentConfig
        }
        try backup(hopeAgentConfig)
        for (key, value) in hooks {
            guard let arr = value as? [Any] else { continue }
            let filtered = arr.filter { !isHopetEntry($0) }
            if filtered.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = filtered
            }
        }
        // hooks 清空后移除 `hooks` 键，但绝不删整个 config.json——它还装着 hope-agent
        // 自己的配置（与 Codex 卸载时可删空 hooks.json 的语义不同）。
        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hopeAgentConfig, options: .atomic)
        return hopeAgentConfig
    }

    private func readHopeAgentConfig() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: hopeAgentConfig), !data.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
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
