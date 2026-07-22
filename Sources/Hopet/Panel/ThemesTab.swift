import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 宠物管理：列出已安装主题、Apply / Delete、上传自定义主题。
/// See preferences.md §3 / §5.3 / §11.6.
struct ThemesTab: View {
    @ObservedObject var themes: ThemeStore
    @State private var showImporter = false
    @State private var showHelp = false
    @State private var pendingDelete: ThemePackage?

    var body: some View {
        PreferencesPaneScaffold("Pet Themes") {
            HStack(spacing: 8) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import Theme…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PixelButtonStyle(tint: PixelPalette.mint, prominent: true))

                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("What to put in a theme folder or .zip")
                .popover(isPresented: $showHelp, arrowEdge: .top) {
                    ThemeImportHelpContent()
                }

                Spacer()
            }

            ForEach(themes.themes, id: \.id) { theme in
                ThemeRow(
                    theme: theme,
                    isActive: themes.activeThemeId == theme.id,
                    onApply: { themes.activeThemeId = theme.id },
                    onDelete: { pendingDelete = theme }
                )
            }

            Text("Import 8 GIFs or a Codex pet package (pet.json + spritesheet.png/webp).")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showImporter) {
            ThemeImportSheet { draft in
                _ = try UserThemeImporter.importTheme(draft)
                themes.reload()
            }
        }
        .alert(item: $pendingDelete) { theme in
            Alert(
                title: Text("Remove '\(theme.name)'?"),
                message: Text("GIF files in \(theme.sourceDirectory?.path ?? "") will be deleted."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteTheme(theme)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func deleteTheme(_ theme: ThemePackage) {
        guard theme.isUserProvided, let dir = theme.sourceDirectory else { return }
        if themes.activeThemeId == theme.id {
            themes.activeThemeId = DefaultTheme.hopi.id
        }
        try? FileManager.default.removeItem(at: dir)
        themes.reload()
    }
}

private struct ThemeRow: View {
    let theme: ThemePackage
    let isActive: Bool
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        PixelCard(
            theme.name.uppercased(),
            accent: isActive ? PixelPalette.mint : .clear,
            titleTint: theme.isUserProvided ? PixelPalette.mint : PixelPalette.sky
        ) {
            HStack(alignment: .top, spacing: 12) {
                ThemePreviewTile(theme: theme)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("v\(theme.version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if theme.isUserProvided {
                            Text("[user]")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let desc = theme.description {
                        Text(desc)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(theme.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if isActive {
                        Text("Active")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    } else {
                        Button("Apply", action: onApply)
                            .buttonStyle(PixelButtonStyle(tint: PixelPalette.sky, prominent: false))
                    }
                    if theme.isUserProvided {
                        Button("Delete", action: onDelete)
                            .buttonStyle(PixelButtonStyle(tint: .red, prominent: false))
                    }
                }
            }
        }
    }
}

/// 主题预览方块：取 idle 动画的首帧渲染（无 idle 时按 PetState 优先级回落）。
private struct ThemePreviewTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let theme: ThemePackage

    var body: some View {
        ZStack {
            Rectangle().fill(PixelPalette.base(colorScheme))
            if let preview = theme.animations[.idle] ?? firstAvailableAnimation {
                FrameAnimationView(animation: preview)
                    .padding(2)
            } else {
                Text("🦭")
                    .font(.system(size: 30))
            }
        }
        .frame(width: 56, height: 56)
        .modifier(PixelChrome(
            cornerRadius: 6,
            accent: .clear,
            strokeWidth: 1.5,
            strokeColor: PixelPalette.stroke
        ))
    }

    private var firstAvailableAnimation: FrameAnimation? {
        PetState.allCases
            .sorted { $0.priority < $1.priority }
            .lazy
            .compactMap { theme.animations[$0] }
            .first
    }
}

// MARK: - Import Sheet

private struct ThemeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: (UserThemeImporter.DraftTheme) throws -> Void

    @State private var name: String = ""
    @State private var gifs: [PetState: URL] = [:]
    @State private var codexPet: CodexPetPackage?
    @State private var errorMessage: String?
    /// 文件夹/压缩包扫描留下的提示与告警（成功也可能伴随警告，例如同 state 多个候选）。
    @State private var scanIssues: [String] = []
    /// 解压 zip 时的临时目录，sheet 关闭时一并清理。
    @State private var temporaryRoot: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Theme")
                .font(.system(size: 14, weight: .bold, design: .monospaced))

            PixelCard("THEME NAME", titleTint: PixelPalette.sky) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("My pixel pet", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                        .background(PixelPalette.cream.opacity(colorScheme == .dark ? 0.10 : 0.80))
                        .overlay(
                            PixelRoundedRectangle(cornerRadius: 4, pixelSize: PixelPalette.pixel)
                                .stroke(PixelPalette.stroke, lineWidth: 1.5)
                        )
                }
            }

            HStack(spacing: 8) {
                Button {
                    pickFolderOrArchive()
                } label: {
                    Label("Choose Folder / Zip…", systemImage: "folder")
                }
                .buttonStyle(PixelButtonStyle(tint: PixelPalette.sky, prominent: false))
                Text("Detects a GIF theme or Codex pet package in a folder or .zip.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let codexPet {
                CodexPetImportSummary(pet: codexPet)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(PetState.allCases, id: \.self) { state in
                            PixelDropSlot(state: state, gifURL: $gifs[state])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)
            }

            statusFooter

            HStack {
                Spacer()
                Button("Cancel") {
                    cleanupTemporary()
                    dismiss()
                }
                .buttonStyle(PixelButtonStyle(tint: .gray, prominent: false))
                Button("Import") { runImport() }
                    .buttonStyle(PixelButtonStyle(tint: PixelPalette.mint, prominent: true))
                    .disabled(!canImport)
            }
        }
        .padding(16)
        .frame(width: 540)
        .background(PixelGridBackground())
        .onDisappear { cleanupTemporary() }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var missingStates: [PetState] {
        PetState.allCases.filter { gifs[$0] == nil }
    }

    private var canImport: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (codexPet != nil || missingStates.isEmpty)
    }

    @ViewBuilder
    private var statusFooter: some View {
        // 三段优先级：error > scanIssues > missing 提示
        if let errorMessage {
            VStack(alignment: .leading, spacing: 4) {
                Text(errorMessage)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
                if !scanIssues.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(scanIssues, id: \.self) { issue in
                                Text("• \(issue)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxHeight: 70)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !scanIssues.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan warnings:")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(scanIssues, id: \.self) { issue in
                            Text("• \(issue)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: 70)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if codexPet == nil, !missingStates.isEmpty {
            Text("Missing: \(missingStates.map(\.rawValue).joined(separator: ", "))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runImport() {
        do {
            try onImport(UserThemeImporter.DraftTheme(name: name, gifs: gifs, codexPet: codexPet))
            cleanupTemporary()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pickFolderOrArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .zip]
        // macOS Sonoma 起 .folder + .zip 同时允许时面板默认拒绝目录；显式 enable。
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyScan(url: url)
    }

    private func applyScan(url: URL) {
        // 重新扫描前清理并清空上一次来源，避免失败后 Import 指向已删除的 zip staging 或旧文件夹。
        cleanupTemporary()
        codexPet = nil
        gifs = [:]
        errorMessage = nil
        scanIssues = []
        do {
            let scan = try UserThemeImporter.scanDirectoryOrArchive(url)
            if let codexPet = scan.codexPet {
                self.codexPet = codexPet
            } else {
                // 当前扫描结果成为唯一来源，不保留已清理 staging 中的旧 GIF URL。
                for (state, src) in scan.gifs {
                    gifs[state] = src
                }
            }
            scanIssues = scan.issues
            temporaryRoot = scan.temporaryRoot
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = scan.suggestedName
            }
            if scan.codexPet == nil, !scan.missing.isEmpty {
                // 不是 fatal——missing 在 footer 已有专门提示位，但仍把当前文件夹缺哪几个写进 issues。
                scanIssues.insert(
                    "Folder/archive is missing: \(scan.missing.map(\.rawValue).joined(separator: ", "))",
                    at: 0
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanupTemporary() {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }
}

/// "?" popover 内容：说明文件夹/压缩包导入需要准备的资源与命名规则。
private struct ThemeImportHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme package requirements")
                .font(.system(size: 12, weight: .bold, design: .monospaced))

            Text("Choose either a Hopet GIF theme or a Codex pet package.")
                .font(.system(size: 11, design: .monospaced))

            VStack(alignment: .leading, spacing: 2) {
                ForEach(PetState.allCases, id: \.self) { state in
                    HStack(spacing: 6) {
                        Circle().fill(state.accentColor).frame(width: 6, height: 6)
                        Text("\(state.rawValue).gif")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.leading, 4)

            Divider()

            Text("Codex pet import")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text("A package must contain pet.json and spritesheet.png or spritesheet.webp. Hopet accepts v1 (1536×1872, 8×9) and current v2 (1536×2288, 8×11) sheets, then maps their standard rows to session states automatically.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Folder import")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text("Pick a folder or a .zip that contains a GIF theme or Codex pet. One level of nesting is accepted; __MACOSX and hidden files are ignored.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Name matching")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text("Case, hyphens, underscores and spaces are ignored when matching: \"Tool Use.gif\", \"tool_use.gif\" and \"tool-use.gif\" all map to tool-use.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("GIF requirements")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text("Real GIF format (not just a renamed file) with at least one frame. Files with non-GIF content or unrecognized names are reported in the import panel.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }
}

/// 导入 Codex pet 后替代 8 个 GIF 槽，明确显示将保留其原始图集。
private struct CodexPetImportSummary: View {
    let pet: CodexPetPackage

    var body: some View {
        PixelCard("CODEX PET DETECTED", titleTint: PixelPalette.mint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(pet.manifest.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(pet.manifest.description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("pet.json + \(pet.layout.spriteSheetWidth)×\(pet.layout.spriteSheetHeight) \(pet.manifest.spritesheetPath) · 8×\(pet.layout.rows) frames · v\(pet.layout.spriteVersionNumber)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Mapped: idle / review / running / run-right / waiting / waving / jumping / failed")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 单个 PetState 的 GIF 拖拽 / 选择槽。
/// 由于 `pickFile()` 立即弹 `NSOpenPanel` modal 接管鼠标事件，原生 `isPressed` 在松开前
/// 就被截断，按下动效几乎渲染不到一帧。这里用 `flashPressed` + 延迟一次 RunLoop 再弹 panel
/// 的方式手动 flash 按下视觉。
private struct PixelDropSlot: View {
    let state: PetState
    @Binding var gifURL: URL?
    @State private var flashPressed = false
    @State private var isTargeted = false

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(state.accentColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.rawValue)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(gifURL?.lastPathComponent ?? "drop or click to choose .gif")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if gifURL != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(PixelDropSlotButtonStyle(
            accent: gifURL == nil ? .clear : state.accentColor,
            forcedPressed: flashPressed || isTargeted
        ))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if url.pathExtension.lowercased() == "gif" { gifURL = url }
                }
            }
            return true
        }
    }

    private func handleTap() {
        // 1. 立即点亮按下视觉。
        withAnimation(.linear(duration: 0.06)) { flashPressed = true }
        // 2. 等一拍让按下帧先渲染，再回弹 + 弹出 NSOpenPanel。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.linear(duration: 0.12)) { flashPressed = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                pickFile()
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gif]
        if panel.runModal() == .OK, let url = panel.url {
            gifURL = url
        }
    }
}

/// PixelDropSlot 专用按钮样式：整个 chrome 区域接受点击；按下时整槽下沉、accent 切到
/// `lemon` 亮色 + 描边加粗，与 `PixelButtonStyle` 的"按入"语言同源但更夸张，
/// 避免 modal 弹出时反馈一闪而过。
private struct PixelDropSlotButtonStyle: ButtonStyle {
    let accent: Color
    let forcedPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || forcedPressed
        return configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(PixelChrome(
                cornerRadius: 6,
                accent: pressed ? PixelPalette.lemon : accent,
                strokeWidth: pressed ? 2.0 : 1.5,
                strokeColor: PixelPalette.stroke
            ))
            .scaleEffect(pressed ? 0.97 : 1.0, anchor: .center)
            .offset(y: pressed ? 3 : 0)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}
