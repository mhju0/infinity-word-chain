import SwiftUI

/// Inherited 자모 wallpaper outside active gameplay.
/// Pattern-legibility option A: any glyph that would touch text, a tile or an icon is left out,
/// so the pattern never sits behind something to read. Cards and buttons cover it anyway.
struct JamoWallpaper: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(ClearZones.self) { anchors in
                GeometryReader { proxy in
                    // Clear zones move every frame while a screen scrolls, but the set of
                    // knocked-out glyphs changes far less often; the canvas redraws only then.
                    JamoCanvas(size: proxy.size,
                               hidden: JamoCanvas.knockouts(size: proxy.size, clear: anchors.map { proxy[$0] }),
                               colorScheme: colorScheme)
                        .equatable()
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
            .background(Palette.background.ignoresSafeArea())
    }
}

private struct JamoCanvas: View, Equatable {
    let size: CGSize
    /// One flag per grid cell, row by row: true where a glyph would touch a clear zone.
    let hidden: [Bool]
    /// Part of the equality so a theme switch redraws in the new wallpaper color.
    let colorScheme: ColorScheme

    nonisolated static func == (lhs: JamoCanvas, rhs: JamoCanvas) -> Bool {
        lhs.size == rhs.size && lhs.colorScheme == rhs.colorScheme && lhs.hidden == rhs.hidden
    }

    /// 15 px glyphs on a 28 px grid in the mockup, scaled like the rest of the layout.
    private static let cell: CGFloat = 38
    private static let glyph: CGFloat = 20
    private static let letters = Array("ㄱㄴㄷㄹㅁㅂㅅㅇㅈㅊㅋㅌㅍㅎ").map(String.init)

    private static func grid(_ size: CGSize) -> (cols: Int, rows: Int) {
        (Int(size.width / cell) + 2, Int(size.height / cell) + 2)
    }

    private static func center(row: Int, col: Int) -> CGPoint {
        let shift = row % 2 == 1 ? cell / 2 : 0
        return CGPoint(x: CGFloat(col) * cell + shift + cell / 2 - 6, y: CGFloat(row) * cell + cell / 2 - 6)
    }

    static func knockouts(size: CGSize, clear: [CGRect]) -> [Bool] {
        let (cols, rows) = grid(size)
        let half = glyph * 0.46
        let zones = clear.map { $0.insetBy(dx: -3, dy: -3) }
        var hidden = [Bool](repeating: false, count: max(0, cols * rows))
        guard !zones.isEmpty else { return hidden }
        var i = 0
        for row in 0..<rows {
            for col in 0..<cols {
                defer { i += 1 }
                let c = center(row: row, col: col)
                let box = CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2)
                hidden[i] = zones.contains(where: { $0.intersects(box) })
            }
        }
        return hidden
    }

    var body: some View {
        Canvas { context, _ in
            let (cols, rows) = Self.grid(size)
            // Lay out the 14 letters once per pass instead of once per glyph.
            let glyphs = Self.letters.map {
                context.resolve(Text($0).font(.pretendardFixed(Self.glyph, .heavy)).foregroundStyle(Palette.wallpaper))
            }
            var i = 0
            for row in 0..<rows {
                for col in 0..<cols {
                    defer { i += 1 }
                    if i < hidden.count && hidden[i] { continue }
                    context.draw(glyphs[(i * 5) % 14], at: Self.center(row: row, col: col))
                }
            }
        }
    }
}

struct ClearZones: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Keep wallpaper glyphs away from this view's own bounds (use on text, not on full-width blocks).
    func clearsWallpaper() -> some View {
        anchorPreference(key: ClearZones.self, value: .bounds) { [$0] }
    }

    func jamoWallpaper() -> some View { modifier(JamoWallpaper()) }

    /// Plain background, no pattern (the game screens).
    func plainBackground() -> some View { background(Palette.background.ignoresSafeArea()) }
}
