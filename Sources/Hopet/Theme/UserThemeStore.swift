import Foundation

/// 扫描 `~/.hopet/themes/<id>/manifest.json` 加载用户主题。
/// 单个主题损坏（manifest 缺失 / 任一 PetState 资源缺失）时跳过该目录并 warn，不影响其他主题。
/// See preferences.md §5.
public enum UserThemeStore {
    public static func scan() -> [ThemePackage] {
        let root = HopetPaths.themes
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        // 排序键 createdAt 与 ThemePackage 一起从 manifest 一次性解出，避免按文件二次解码。
        var loaded: [(Date, ThemePackage)] = []
        for dir in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            do {
                loaded.append(try loadTheme(at: dir))
            } catch {
                HopetLog.warn("UserThemeStore: skip \(dir.lastPathComponent): \(error)")
            }
        }
        // 用户主题按 createdAt 升序（preferences.md §9）。
        return loaded.sorted { ($0.0, $0.1.name) < ($1.0, $1.1.name) }.map(\.1)
    }

    private static func loadTheme(at dir: URL) throws -> (Date, ThemePackage) {
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(UserThemeManifest.self, from: data)
        guard manifest.schemaVersion == 1 else {
            throw UserThemeError.unknownSchemaVersion(manifest.schemaVersion)
        }

        let animations: [PetState: FrameAnimation]
        let description: String
        switch manifest.assetFormat ?? .gif {
        case .gif:
            var gifAnimations: [PetState: FrameAnimation] = [:]
            for state in PetState.allCases {
                let gif = dir.appendingPathComponent("\(state.rawValue).gif")
                guard FileManager.default.fileExists(atPath: gif.path) else {
                    throw UserThemeError.missingGIF(state)
                }
                gifAnimations[state] = .gifFile(url: gif)
            }
            animations = gifAnimations
            description = "User theme · imported \(formatted(manifest.createdAt))"

        case .codexPet:
            guard let codexPet = manifest.codexPet else {
                throw UserThemeError.missingCodexPetManifest
            }
            guard let layout = codexPet.layout else {
                throw UserThemeError.unsupportedCodexPetVersion(codexPet.spriteVersionNumber)
            }
            let spriteSheet = dir.appendingPathComponent(codexPet.spritesheetPath)
            guard FileManager.default.fileExists(atPath: spriteSheet.path) else {
                throw UserThemeError.missingCodexSpriteSheet(codexPet.spritesheetPath)
            }
            animations = Dictionary(uniqueKeysWithValues: PetState.allCases.map { state in
                (
                    state,
                    .codexPetSpriteSheet(
                        url: spriteSheet,
                        row: CodexPetStateMapping.animation(for: state),
                        layout: layout,
                        framesPerSecond: 8
                    )
                )
            })
            let sourceDescription = codexPet.kind ?? "v\(layout.spriteVersionNumber)"
            description = "Codex pet · \(sourceDescription) · imported \(formatted(manifest.createdAt))"
        }

        let pack = ThemePackage(
            id: manifest.id,
            name: manifest.name,
            version: "1",
            author: nil,
            description: description,
            glyphs: [:],
            animations: animations,
            isUserProvided: true,
            sourceDirectory: dir
        )
        return (manifest.createdAt, pack)
    }

    private static func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// `manifest.json` 的 schema。可选格式字段保持与已有 GIF 主题的 schemaVersion 1 兼容。
enum UserThemeAssetFormat: String, Codable {
    case gif
    case codexPet = "codex-pet"
}

struct UserThemeManifest: Codable {
    var schemaVersion: Int = 1
    let id: String
    let name: String
    var createdAt: Date = Date()
    var assetFormat: UserThemeAssetFormat?
    var codexPet: CodexPetManifest?

    init(
        id: String,
        name: String,
        createdAt: Date = Date(),
        assetFormat: UserThemeAssetFormat? = nil,
        codexPet: CodexPetManifest? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.assetFormat = assetFormat
        self.codexPet = codexPet
    }
}

enum UserThemeError: LocalizedError {
    case unknownSchemaVersion(Int)
    case missingGIF(PetState)
    case missingCodexPetManifest
    case missingCodexSpriteSheet(String)
    case unsupportedCodexPetVersion(Int?)

    var errorDescription: String? {
        switch self {
        case .unknownSchemaVersion(let v): return "unknown manifest schemaVersion \(v)"
        case .missingGIF(let s):           return "missing GIF for state '\(s.rawValue)'"
        case .missingCodexPetManifest:     return "missing Codex pet metadata"
        case .missingCodexSpriteSheet(let path): return "missing Codex pet \(path)"
        case .unsupportedCodexPetVersion(let version):
            return "unsupported Codex pet spriteVersionNumber \(version.map(String.init) ?? "missing")"
        }
    }
}
