import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 导入用户自定义主题：校验 8 个 PetState GIF 或 Codex pet 图集、复制到 `~/.hopet/themes/<id>/`、写 manifest。
/// 校验失败整次回滚（删除半成品目录）。See preferences.md §5.3.
public enum UserThemeImporter {
    /// 用户填写的主题名，加上 8 个 GIF 源 URL 或已校验的 Codex pet 包。
    public struct DraftTheme {
        public var name: String
        public var gifs: [PetState: URL]
        public var codexPet: CodexPetPackage?

        public init(name: String, gifs: [PetState: URL] = [:], codexPet: CodexPetPackage? = nil) {
            self.name = name
            self.gifs = gifs
            self.codexPet = codexPet
        }
    }

    /// 执行导入。成功返回新主题目录 URL，失败抛错并保证目录已清理。
    @discardableResult
    public static func importTheme(_ draft: DraftTheme) throws -> URL {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyName }

        if let codexPet = draft.codexPet {
            return try importCodexPet(codexPet, name: trimmed)
        }

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

    private static func importCodexPet(_ pet: CodexPetPackage, name: String) throws -> URL {
        try validateCodexPet(pet)

        let id = makeId(from: name)
        let dir = HopetPaths.themes.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(
                at: pet.spriteSheetURL,
                to: dir.appendingPathComponent(pet.manifest.spritesheetPath)
            )
            let manifest = UserThemeManifest(
                id: id,
                name: name,
                assetFormat: .codexPet,
                codexPet: pet.manifest
            )
            try writeManifest(manifest, to: dir)
            return dir
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
    }

    private static func writeManifest(_ manifest: UserThemeManifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    // MARK: - Directory / Archive scan

    /// 扫描文件夹或 .zip 压缩包，按 PetState rawValue 匹配 GIF 文件。
    /// 命名匹配在「忽略大小写、忽略 `-`/`_`/空格」后比对，所以
    /// `idle.gif` / `IDLE.gif` / `tool-use.gif` / `tool_use.gif` / `Tool Use.gif` 都能识别。
    public struct DirectoryScan {
        public let suggestedName: String
        public let gifs: [PetState: URL]
        public let missing: [PetState]
        /// 识别到 Codex pet 时不再填 GIF 槽；导入时直接保留原始 PNG / WebP 图集。
        public let codexPet: CodexPetPackage?
        /// 被跳过/警告的文件信息，例如不识别的文件名、扩展名不是 .gif、同一状态出现多个候选。
        public let issues: [String]
        /// 仅在 zip 解压时设置：sheet 关闭时由调用方负责清理（取消则尽快清理临时目录）。
        public let temporaryRoot: URL?
    }

    public static func scanDirectoryOrArchive(_ url: URL) throws -> DirectoryScan {
        let fm = FileManager.default
        var tempRoot: URL? = nil
        var scanSucceeded = false
        defer {
            if !scanSucceeded, let tempRoot {
                try? fm.removeItem(at: tempRoot)
            }
        }
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

        if let codexPet = try findCodexPet(under: root) {
            let scan = DirectoryScan(
                suggestedName: codexPet.manifest.displayName,
                gifs: [:],
                missing: [],
                codexPet: codexPet,
                issues: ["Recognized Codex pet: \(codexPet.manifest.displayName). Its 9 animation rows will be mapped to Hopet states."],
                temporaryRoot: tempRoot
            )
            scanSucceeded = true
            return scan
        }

        // 收集 root 下所有 .gif 文件（一层目录 + 直接根层；忽略 __MACOSX、隐藏文件）。
        let candidates = collectGIFFiles(under: root)
        guard !candidates.isEmpty else {
            throw ImportError.noGIFsInSource
        }

        var matches: [PetState: URL] = [:]
        var issues: [String] = []
        // 同一 state 出现多个候选时取第一个，其余记入 issues。
        for url in candidates {
            let normalized = normalize(url.deletingPathExtension().lastPathComponent)
            guard let state = matchState(normalized: normalized) else {
                issues.append("Skipped '\(url.lastPathComponent)' — name does not match any pet state.")
                continue
            }
            if matches[state] == nil {
                matches[state] = url
            } else {
                issues.append("Multiple GIFs match '\(state.rawValue)'; using '\(matches[state]!.lastPathComponent)', skipped '\(url.lastPathComponent)'.")
            }
        }

        let missing = PetState.allCases.filter { matches[$0] == nil }
        let suggestedName = suggestedNameFrom(url: url, isArchive: ext == "zip")
        let scan = DirectoryScan(
            suggestedName: suggestedName,
            gifs: matches,
            missing: missing,
            codexPet: nil,
            issues: issues,
            temporaryRoot: tempRoot
        )
        scanSucceeded = true
        return scan
    }

    /// Codex pet 可以直接位于所选根目录，也可以被打包在单层目录中。
    private static func findCodexPet(under root: URL) throws -> CodexPetPackage? {
        let fm = FileManager.default
        var directories = [root]
        if let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where entry.lastPathComponent != "__MACOSX" {
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: entry.path, isDirectory: &isDir)
                if isDir.boolValue { directories.append(entry) }
            }
        }

        let packages = try directories.compactMap { directory -> CodexPetPackage? in
            let manifestURL = directory.appendingPathComponent("pet.json")
            guard fm.fileExists(atPath: manifestURL.path) else { return nil }
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(CodexPetManifest.self, from: data)
            guard isSupportedSpriteSheetPath(manifest.spritesheetPath) else {
                throw ImportError.invalidCodexPet("pet.json must use spritesheet.png or spritesheet.webp.")
            }
            let package = CodexPetPackage(
                directory: directory,
                spriteSheetURL: directory.appendingPathComponent(manifest.spritesheetPath),
                manifest: manifest,
                layout: try layout(for: manifest)
            )
            try validateCodexPet(package)
            return package
        }
        if packages.count > 1 { throw ImportError.multipleCodexPets }
        return packages.first
    }

    private static func validateCodexPet(_ pet: CodexPetPackage) throws {
        guard isSupportedSpriteSheetPath(pet.manifest.spritesheetPath),
              !pet.manifest.id.isEmpty,
              !pet.manifest.displayName.isEmpty,
              !pet.manifest.description.isEmpty
        else {
            throw ImportError.invalidCodexPet("pet.json is missing required metadata.")
        }
        guard CodexPetSpriteLayout.resolve(spriteVersionNumber: pet.manifest.spriteVersionNumber) == pet.layout else {
            throw ImportError.invalidCodexPet("pet.json has an unsupported spriteVersionNumber.")
        }
        let expectedImageType: String
        switch pet.spriteSheetURL.pathExtension.lowercased() {
        case "png": expectedImageType = "public.png"
        case "webp": expectedImageType = "org.webmproject.webp"
        default:
            throw ImportError.invalidCodexPet("spritesheet must be PNG or WebP.")
        }
        guard let source = CGImageSourceCreateWithURL(pet.spriteSheetURL as CFURL, nil),
              CGImageSourceGetType(source) as String? == expectedImageType,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == pet.layout.spriteSheetWidth,
              image.height == pet.layout.spriteSheetHeight
        else {
            throw ImportError.invalidCodexPet(
                "spritesheet must be a readable \(pet.layout.spriteSheetWidth)×\(pet.layout.spriteSheetHeight) \(pet.spriteSheetURL.pathExtension.uppercased()) image for spriteVersionNumber \(pet.layout.spriteVersionNumber)."
            )
        }
        do {
            try CodexPetSpriteSheetCache.validateStandardAnimations(at: pet.spriteSheetURL, layout: pet.layout)
        } catch {
            throw ImportError.invalidCodexPet(error.localizedDescription)
        }
    }

    private static func layout(for manifest: CodexPetManifest) throws -> CodexPetSpriteLayout {
        guard let layout = manifest.layout else {
            throw ImportError.invalidCodexPet("unsupported spriteVersionNumber '\(manifest.spriteVersionNumber.map(String.init) ?? "missing")'.")
        }
        return layout
    }

    private static func isSupportedSpriteSheetPath(_ path: String) -> Bool {
        path == "spritesheet.png" || path == "spritesheet.webp"
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
    case invalidCodexPet(String)
    case multipleCodexPets
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
            return "No Hopet GIF theme or Codex pet package was found in the folder or archive."
        case .invalidCodexPet(let reason):
            return "Invalid Codex pet: \(reason)"
        case .multipleCodexPets:
            return "More than one Codex pet package was found. Select a folder or archive with exactly one pet."
        case .unzipFailed(let reason):
            return "Failed to unzip archive: \(reason)"
        }
    }
}
