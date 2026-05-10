import SwiftUI

/// 每个 Preferences Tab 的统一外壳：顶部 14pt monospaced bold 标题 + 12pt 内边距 + 自动滚动。
/// 把字体度量、间距、像素底色集中在此处，避免每个 Tab 各拍脑袋。
/// See preferences.md §11.5.
struct PreferencesPaneScaffold<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder _ content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(PixelPalette.ink(colorScheme))
                    .padding(.horizontal, 4)
                content()
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
