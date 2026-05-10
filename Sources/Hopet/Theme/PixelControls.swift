import SwiftUI

/// 像素风卡片：`PixelChrome` 的便捷外壳，统一卡片 padding 与圆角。
/// See preferences.md §11.2.2.
struct PixelCard<Content: View>: View {
    let title: String?
    let accent: Color
    let titleTint: Color
    let cornerRadius: CGFloat
    let content: () -> Content

    init(
        _ title: String? = nil,
        accent: Color = .clear,
        titleTint: Color = PixelPalette.sky,
        cornerRadius: CGFloat = 8,
        @ViewBuilder _ content: @escaping () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.titleTint = titleTint
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                PixelCardCaption(title: title, tint: titleTint)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
            .padding(12)
            .modifier(PixelChrome(
                cornerRadius: cornerRadius,
                accent: accent,
                strokeWidth: 1.5,
                strokeColor: PixelPalette.stroke
            ))
    }
}

private struct PixelCardCaption: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .overlay(Rectangle().stroke(PixelPalette.stroke, lineWidth: 1))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(PixelPalette.ink(colorScheme))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.36))
                .frame(height: 2)
                .offset(y: 5)
        }
    }
}

/// 像素方块开关：替代 SwiftUI `Toggle`。两态：
/// - off：灰底空心方框 + 黑描边
/// - on ：accent 染色实心方框 + 黑描边
///
/// 自绘按钮显式透传 toggle 语义，避免把系统 checkbox 视觉混进像素面板。
struct PixelToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isOn: Bool
    let tint: Color

    init(isOn: Binding<Bool>, tint: Color = .accentColor) {
        self._isOn = isOn
        self.tint = tint
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            box
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAction { isOn.toggle() }
    }

    private var box: some View {
        ZStack {
            if isOn {
                Rectangle().fill(PixelPalette.stroke)
                    .frame(width: 20, height: 20)
                Rectangle().fill(tint)
                    .frame(width: 16, height: 16)
            } else {
                Rectangle().fill(PixelPalette.stroke)
                    .frame(width: 20, height: 20)
                Rectangle().fill(PixelPalette.base(colorScheme).opacity(0.92))
                    .frame(width: 16, height: 16)
                Rectangle().fill(PixelPalette.sky.opacity(colorScheme == .dark ? 0.16 : 0.24))
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
}

/// 单行 `label + PixelToggle` 行：BehaviorTab / NotificationsTab 等多 Toggle 面板的复用单位。
/// See preferences.md §11.6.
struct PixelToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
            Spacer()
            PixelToggle(isOn: $isOn)
        }
    }
}

/// 像素分段控件：替代 SwiftUI `Picker(.segmented)`。每段是 `PixelButtonStyle`，
/// 选中段切到 prominent 风格，未选中段保持 secondary。
/// See preferences.md §11.2.2 / §11.6.
struct PixelSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    let tint: Color

    init(selection: Binding<Value>, options: [(Value, String)], tint: Color = .accentColor) {
        self._selection = selection
        self.options = options
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                Button(opt.label) { selection = opt.value }
                    .buttonStyle(PixelButtonStyle(
                        tint: tint,
                        prominent: selection == opt.value
                    ))
            }
        }
    }
}
