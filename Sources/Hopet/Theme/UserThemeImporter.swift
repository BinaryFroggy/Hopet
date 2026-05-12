import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 导入用户自定义主题：校验 8 个 PetState GIF 完备性、复制到 `~/.hopet/themes/<id>/`、写 manifest。
/// 校验失败整次回滚（删除半成品目录）。See preferences.md §5.3.
public enum UserThemeImporter {
    /// 用户填写的主题名 + 8 个 GIF 源 URL。
    public struct DraftTheme {
        public var name: String
        public var gifs: [PetState: URL]
        public init(name: String, gifs: [PetState: URL]) {
            self.name = name
            self.gifs = gifs
        }
    }

    /// 执行导入。成功返回新主题目录 URL，失败抛错并保证目录已清理。
    @discardableResult
    public static func importTheme(_ draft: DraftTheme) throws -> URL {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyName }

        let missing = PetState.allCases.filter { draft.gifs[$0] == nil }
        guard missing.isEmpty else { throw ImportError.missingStates(missing) }

        for (state, url) in draft.gifs {
            try validateGIF(url, state: state)
        }

        let id = makeId(from: trimmed)
        let dir = HopetPaths.themes.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (state, src) in draft.gifs {
                let dst = dir.appendingPathComponent("\(state.rawValue).gif")
                try fm.copyItem(at: src, to: dst)
            }
            let manifest = UserThemeManifest(id: id, name: trimmed)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
            return dir
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
    }

    private static func validateGIF(_ url: URL, state: PetState) throws {
        // UTI 校验：避免改名 .gif 绕过。
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type != .gif, !type.conforms(to: .gif) {
            throw ImportError.invalidGIF(state, "not a GIF (uti=\(type.identifier))")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImportError.invalidGIF(state, "cannot open as image source")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw ImportError.invalidGIF(state, "zero frames")
        }
    }

    // MARK: - Directory / Archive scan

    /// 扫描文件夹或 .zip 压缩包，按 PetState rawValue 匹配 GIF 文件。
    /// 命名匹配在「忽略大小写、忽略 `-`/`_`/空格」后比对，所以
    /// `idle.gif` / `IDLE.gif` / `tool-use.gif` / `tool_use.gif` / `Tool Use.gif` 都能识别。
    public struct DirectoryScan {
        public let suggestedName: String
        public let gifs: [PetState: URL]
        public let missing: [PetState]
        /// 被跳过/警告的文件信息，例如不识别的文件名、扩展名不是 .gif、同一状态出现多个候选。
        public let issues: [String]
        /// 仅在 zip 解压时设置：sheet 关闭时由调用方负责清理（取消则尽快清理临时目录）。
        public let temporaryRoot: URL?
    }

    public static func scanDirectoryOrArchive(_ url: URL) throws -> DirectoryScan {
        let fm = FileManager.default
        var tempRoot: URL? = nil
        let root: URL

        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            let dest = fm.temporaryDirectory
                .appendingPathComponent("hopet-import-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try unzip(url, to: dest)
            tempRoot = dest
            root = dest
        } else {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                throw ImportError.notADirectoryOrZip
            }
            root = url
        }

        // 收集 root 下所有 .gif 文件（一层目录 + 直接根层；忽略 __MACOSX、隐藏文件）。
        let candidates = collectGIFFiles(under: root)
        guard !candidates.isEmpty else {
            throw ImportError.noGIFsInSource
        }

        var matches: [PetState: URL] = [:]
        var issues: [String] = []
        var usedURLs = Set<URL>()

        // 同一 state 出现多个候选时取第一个，其余记入 issues。
        for url in candidates {
            let normalized = normalize(url.deletingPathExtension().lastPathComponent)
            guard let state = matchState(normalized: normalized) else {
                issues.append("Skipped '\(url.lastPathComponent)' — name does not match any pet state.")
                continue
            }
            if matches[state] == nil {
                matches[state] = url
                usedURLs.insert(url)
            } else {
                issues.append("Multiple GIFs match '\(state.rawValue)'; using '\(matches[state]!.lastPathComponent)', skipped '\(url.lastPathComponent)'.")
            }
        }

        let missing = PetState.allCases.filter { matches[$0] == nil }
        let suggestedName = suggestedNameFrom(url: url, isArchive: ext == "zip")
        return DirectoryScan(
            suggestedName: suggestedName,
            gifs: matches,
            missing: missing,
            issues: issues,
            temporaryRoot: tempRoot
        )
    }

    /// 一层扁平扫描 + 至多一级子目录。压缩包里常有 `themepack/idle.gif` 嵌套，
    /// 但再深就不再追，避免捡到隔壁 demo 资源。
    private static func collectGIFFiles(under root: URL) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []

        func appendGIFs(in dir: URL) {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries {
                let name = entry.lastPathComponent
                if name == "__MACOSX" { continue }
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: entry.path, isDirectory: &isDir)
                if !isDir.boolValue, entry.pathExtension.lowercased() == "gif" {
                    out.append(entry)
                }
            }
        }

        appendGIFs(in: root)
        // 仅当 root 自身没有 GIF 时，再到一级子目录里找——避免根 + 子目录混淆。
        if out.isEmpty,
           let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
           ) {
            for entry in entries {
                let name = entry.lastPathComponent
                if name == "__MACOSX" { continue }
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: entry.path, isDirectory: &isDir)
                if isDir.boolValue { appendGIFs(in: entry) }
            }
        }
        return out
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func matchState(normalized: String) -> PetState? {
        PetState.allCases.first { normalize($0.rawValue) == normalized }
    }

    private static func suggestedNameFrom(url: URL, isArchive: Bool) -> String {
        let base = isArchive ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        return base.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func unzip(_ zip: URL, to dest: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dest.path]
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
        } catch {
            throw ImportError.unzipFailed(error.localizedDescription)
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let errOut = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let snippet = errOut.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
            throw ImportError.unzipFailed("ditto exited \(p.terminationStatus). \(snippet)")
        }
    }

    /// `user.<slug>.<uuid8>` 形如 user.cat.7f3a8b1c
    private static func makeId(from name: String) -> String {
        let slug = slugify(name)
        let uuid = UUID().uuidString.prefix(8).lowercased()
        return "user.\(slug.isEmpty ? "theme" : slug).\(uuid)"
    }

    private static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastDash = false
            } else if ch.isWhitespace || ch == "-" || ch == "_" {
                if !lastDash, !out.isEmpty {
                    out.append("-")
                    lastDash = true
                }
            }
        }
        if out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(24))
    }
}

public enum ImportError: LocalizedError {
    case emptyName
    case missingStates([PetState])
    case invalidGIF(PetState, String)
    case notADirectoryOrZip
    case noGIFsInSource
    case unzipFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Theme name is empty."
        case .missingStates(let states):
            return "Missing GIFs: \(states.map(\.rawValue).joined(separator: ", "))"
        case .invalidGIF(let state, let reason):
            return "Invalid GIF for '\(state.rawValue)': \(reason)"
        case .notADirectoryOrZip:
            return "Selected item is not a folder or a .zip archive."
        case .noGIFsInSource:
            return "No .gif files found at the top level of the folder or archive."
        case .unzipFailed(let reason):
            return "Failed to unzip archive: \(reason)"
        }
    }
}
