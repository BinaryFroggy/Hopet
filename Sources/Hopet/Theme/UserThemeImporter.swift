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

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Theme name is empty."
        case .missingStates(let states):
            return "Missing GIFs: \(states.map(\.rawValue).joined(separator: ", "))"
        case .invalidGIF(let state, let reason):
            return "Invalid GIF for '\(state.rawValue)': \(reason)"
        }
    }
}
