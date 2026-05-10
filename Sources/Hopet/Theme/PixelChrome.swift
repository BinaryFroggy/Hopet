import SwiftUI

/// 像素风视觉的色值与几何 token。所有面板控件与气泡共用同一组数值，
/// 保证从宠物气泡到 Preferences 卡片像素级同源。See preferences.md §11.3.
enum PixelPalette {
    /// 像素 pitch：圆角阶梯 / 阴影偏移按这个量化。
    static let pixel: CGFloat = 2

    /// 描边色：硬黑（亮 / 暗共用，不随主题变化）。
    static let stroke = Color.black.opacity(0.85)

    /// 块状阴影色。
    static let shadow = Color.black.opacity(0.22)

    /// 参考图同源的像素主色：蓝描边 + 粉 / 黄 / 青 / 绿点缀。
    static let chromeBlue = Color(red: 0.04, green: 0.42, blue: 0.86)
    static let candyPink = Color(red: 0.98, green: 0.50, blue: 0.78)
    static let lemon = Color(red: 0.99, green: 0.93, blue: 0.38)
    static let mint = Color(red: 0.66, green: 0.92, blue: 0.48)
    static let sky = Color(red: 0.56, green: 0.92, blue: 0.98)
    static let cream = Color(red: 1.00, green: 1.00, blue: 0.94)

    /// 卡片底色：light 近白冷调，dark 深冷调。
    static func base(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.16)
            : Color(red: 0.97, green: 0.97, blue: 0.99)
    }

    /// 面板底色：light 使用参考图的淡蓝网格；dark 保留冷暗底但提高蓝色可读性。
    static func panelBase(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.08, green: 0.10, blue: 0.14)
            : Color(red: 0.84, green: 0.96, blue: 1.00)
    }

    static func panelLowerBand(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? candyPink.opacity(0.16) : candyPink.opacity(0.26)
    }

    static func gridLine(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.58)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : chromeBlue
    }

    static func mutedInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.52)
    }

    /// 主题强调色覆盖底色的染色比例。dark 拉高饱和度。
    static func accentTint(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.40 : 0.10
    }

    /// 顶部高光带不透明度。dark 压暗避免过曝。
    static func topHighlight(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.18 : 0.45
    }
}

/// Preferences 的淡蓝 / 粉色像素网格背景。只画直线与矩形色带，避免现代渐变感。
/// See preferences.md §11.3.
struct PixelGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(PixelPalette.panelBase(colorScheme))
            )

            let lowerBand = CGRect(
                x: 0,
                y: size.height * 0.68,
                width: size.width,
                height: size.height * 0.32
            )
            context.fill(Path(lowerBand), with: .color(PixelPalette.panelLowerBand(colorScheme)))

            let cell: CGFloat = 24
            var grid = Path()
            var x: CGFloat = 0
            while x <= size.width {
                grid.move(to: CGPoint(x: x.rounded(.down) + 0.5, y: 0))
                grid.addLine(to: CGPoint(x: x.rounded(.down) + 0.5, y: size.height))
                x += cell
            }
            var y: CGFloat = 0
            while y <= size.height {
                grid.move(to: CGPoint(x: 0, y: y.rounded(.down) + 0.5))
                grid.addLine(to: CGPoint(x: size.width, y: y.rounded(.down) + 0.5))
                y += cell
            }
            context.stroke(grid, with: .color(PixelPalette.gridLine(colorScheme)), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

/// 8-bit 像素风外壳：阶梯像素圆角 + 主体填充 + 顶部高光 + 块状阴影。所有几何沿 `pixelSize` 方格对齐，
/// 圆角处呈现可见的 2pt 颗粒阶梯——视觉上对齐参考素材的复古 UI 边缘，与小海豹 sprite 同语言。
/// 描边宽度 / 颜色独立可调：leader session 偏好略粗的黑描边（强调），其余气泡保持基础粗细。
///
/// 配色随系统 colorScheme 切换：
/// - light：近白冷调底 + accent 10% 轻染 + 顶部白高光，搭配系统 .primary 黑字。
/// - dark：深冷调底 + accent 40% 强染（"夜晚饱和度拉高"），顶高光压暗，搭配 .primary 白字
///   仍保持 4:1+ 对比度（包括最亮的 askUser 黄）。
///
/// See preferences.md §11.2.1.
struct PixelChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let accent: Color
    let strokeWidth: CGFloat
    let strokeColor: Color

    func body(content: Content) -> some View {
        let pixel = PixelPalette.pixel
        let strokeInset = strokeWidth
        let baseFill = PixelPalette.base(colorScheme)
        let accentTint = PixelPalette.accentTint(colorScheme)
        let topHighlight = PixelPalette.topHighlight(colorScheme)

        return content
            .padding(strokeInset + 1)  // 让内容不撞到内层亮边
            .background(
                GeometryReader { _ in
                    let cr = self.cornerRadius
                    let outer = PixelRoundedRectangle(cornerRadius: cr, pixelSize: pixel)
                    let inner = PixelRoundedRectangle(
                        cornerRadius: max(pixel, cr - strokeInset),
                        pixelSize: pixel
                    )
                    ZStack {
                        // 1. 块状像素阴影：硬偏移、无模糊，边缘也是阶梯像素。
                        outer
                            .fill(PixelPalette.shadow)
                            .offset(x: 0, y: pixel * 2)
                        // 2. 描边底（外层 shape 整面填描边色，内层填浅色后只剩 strokeInset 宽的描边）。
                        outer.fill(strokeColor)
                        // 3. 内层：base 主体 + accent 染色（夜晚比例更高） + 顶部高光带。padding(strokeInset) 让其向内缩。
                        ZStack {
                            inner.fill(baseFill)
                            inner.fill(accent.opacity(accentTint))
                            // 顶部 4px 像素高光带，强调"自上而来的光源"。
                            inner
                                .fill(Color.white.opacity(topHighlight))
                                .mask(
                                    VStack(spacing: 0) {
                                        Rectangle().frame(height: pixel * 2)
                                        Spacer(minLength: 0)
                                    }
                                )
                        }
                        .padding(strokeInset)
                    }
                }
            )
    }
}

/// 像素化圆角矩形：把 4 个圆角拆成 `pixelSize` 大小的方格阶梯，整体呈现 8-bit UI 边缘的颗粒感。
/// 对每个角，按距离角心的圆形判定填哪些方格；中心由两条贯穿矩形构成，避免任何角度漏接。
///
/// See preferences.md §11.2.1.
struct PixelRoundedRectangle: Shape {
    let cornerRadius: CGFloat
    let pixelSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        // 中央贯通条：上下穿过的中柱 + 左右穿过的中横，两者并集 = 矩形 - 4 个角的方形空洞。
        if rect.width > 2 * r {
            path.addRect(CGRect(x: rect.minX + r, y: rect.minY,
                                width: rect.width - 2 * r, height: rect.height))
        }
        if rect.height > 2 * r {
            path.addRect(CGRect(x: rect.minX, y: rect.minY + r,
                                width: rect.width, height: rect.height - 2 * r))
        }

        // 4 个角：grid 采样，距离 corner anchor < r 的方格填入。
        let cells = max(1, Int(round(r / pixelSize)))
        guard cells > 0 else { return path }
        let cell = r / CGFloat(cells)
        let r2 = CGFloat(cells * cells)
        for cy in 0..<cells {
            for cx in 0..<cells {
                let dx = CGFloat(cells) - CGFloat(cx) - 0.5
                let dy = CGFloat(cells) - CGFloat(cy) - 0.5
                guard dx * dx + dy * dy <= r2 else { continue }
                let ox = CGFloat(cx) * cell
                let oy = CGFloat(cy) * cell
                // top-left
                path.addRect(CGRect(x: rect.minX + ox, y: rect.minY + oy,
                                    width: cell, height: cell))
                // top-right
                path.addRect(CGRect(x: rect.maxX - ox - cell, y: rect.minY + oy,
                                    width: cell, height: cell))
                // bottom-left
                path.addRect(CGRect(x: rect.minX + ox, y: rect.maxY - oy - cell,
                                    width: cell, height: cell))
                // bottom-right
                path.addRect(CGRect(x: rect.maxX - ox - cell, y: rect.maxY - oy - cell,
                                    width: cell, height: cell))
            }
        }
        return path
    }
}

/// 8-bit 风按钮样式。
/// - prominent=true：实色填充（主操作）。
/// - prominent=false：浅色填充 + 深描边（次操作）。
/// - compact=true：缩小字号 / padding / 描边粗细，给 Tab 栏等横排密集场合用。
/// 共同点：圆角 4px、硬黑描边、块状下沿、内部高光；按下时整体下移模拟"按入"。
///
/// See preferences.md §11.2.1.
struct PixelButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color
    let prominent: Bool
    let compact: Bool

    init(tint: Color, prominent: Bool, compact: Bool = false) {
        self.tint = tint
        self.prominent = prominent
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let pressed = configuration.isPressed
        let fontSize: CGFloat = compact ? 11 : 12
        let padH: CGFloat = compact ? 10 : 14
        let padV: CGFloat = compact ? 5 : 7
        let stroke: CGFloat = compact ? 1.2 : 1.5
        return configuration.label
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .foregroundStyle(prominent ? Color.white : PixelPalette.ink(colorScheme))
            .background(
                ZStack {
                    if !pressed {
                        shape
                            .fill(PixelPalette.stroke)
                            .offset(x: 0, y: 2)
                    }
                    shape.fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.22)))
                    shape.stroke(PixelPalette.stroke, lineWidth: stroke)
                    shape
                        .inset(by: stroke)
                        .stroke(Color.white.opacity(prominent ? 0.45 : 0.60), lineWidth: 1)
                }
            )
            .offset(x: 0, y: pressed ? 2 : 0)
            .animation(.linear(duration: 0.05), value: pressed)
    }
}

extension View {
    /// 便捷：用 `PixelChrome` 包裹任意 View。See preferences.md §11.2.
    func pixelChrome(
        cornerRadius: CGFloat = 6,
        accent: Color = .clear,
        strokeWidth: CGFloat = 1.5,
        strokeColor: Color = PixelPalette.stroke
    ) -> some View {
        modifier(PixelChrome(
            cornerRadius: cornerRadius,
            accent: accent,
            strokeWidth: strokeWidth,
            strokeColor: strokeColor
        ))
    }
}
