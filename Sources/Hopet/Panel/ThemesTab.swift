import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 宠物管理：列出已安装主题、Apply / Delete、上传自定义主题。
/// See preferences.md §3 / §5.3 / §11.6.
struct ThemesTab: View {
    @ObservedObject var themes: ThemeStore
    @State private var showImporter = false
    @State private var pendingDelete: ThemePackage?

    var body: some View {
        PreferencesPaneScaffold("Pet Themes") {
            Button {
                showImporter = true
            } label: {
                Label("Import Theme…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PixelButtonStyle(tint: .accentColor, prominent: true))

            ForEach(themes.themes, id: \.id) { theme in
                ThemeRow(
                    theme: theme,
                    isActive: themes.activeThemeId == theme.id,
                    onApply: { themes.activeThemeId = theme.id },
                    onDelete: { pendingDelete = theme }
                )
            }

            Text("Custom themes live in ~/.hopet/themes/. Each must provide 8 GIFs (one per pet state).")
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
            accent: isActive ? .accentColor : .clear,
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
                            .buttonStyle(PixelButtonStyle(tint: .accentColor, prominent: false))
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
    @State private var errorMessage: String?

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
            .frame(maxHeight: 300)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !missingStates.isEmpty {
                Text("Missing: \(missingStates.map(\.rawValue).joined(separator: ", "))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PixelButtonStyle(tint: .gray, prominent: false))
                Button("Import") { runImport() }
                    .buttonStyle(PixelButtonStyle(tint: .accentColor, prominent: true))
                    .disabled(!canImport)
            }
        }
        .padding(16)
        .frame(width: 520)
        .background(PixelGridBackground())
    }

    @Environment(\.colorScheme) private var colorScheme

    private var missingStates: [PetState] {
        PetState.allCases.filter { gifs[$0] == nil }
    }

    private var canImport: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && missingStates.isEmpty
    }

    private func runImport() {
        do {
            try onImport(UserThemeImporter.DraftTheme(name: name, gifs: gifs))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 单个 PetState 的 GIF 拖拽 / 选择槽。
private struct PixelDropSlot: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: PetState
    @Binding var gifURL: URL?

    var body: some View {
        Button(action: pickFile) {
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
                Spacer()
                if gifURL != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .modifier(PixelChrome(
            cornerRadius: 6,
            accent: gifURL == nil ? .clear : state.accentColor,
            strokeWidth: 1.5,
            strokeColor: PixelPalette.stroke
        ))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
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
