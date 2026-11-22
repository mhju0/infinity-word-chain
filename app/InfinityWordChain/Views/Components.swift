import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TextStyle.button)
            .foregroundStyle(Palette.onFill)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .background(enabled ? Palette.fill : Palette.muted, in: .rect(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.85 : enabled ? 1 : 0.55)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TextStyle.button)
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .background(Palette.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TextStyle.buttonSmall)
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 44)
            .background(Palette.card, in: .rect(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { .init() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { .init() }
}
extension ButtonStyle where Self == SmallButtonStyle {
    static var small: SmallButtonStyle { .init() }
}

func endingHighlightedWord(_ word: String) -> Text {
    Text(String(word.dropLast())).foregroundColor(Palette.ink) +
    Text(String(word.suffix(1))).foregroundColor(Palette.accent)
}

struct CardShadow: ViewModifier {
    var radius: CGFloat = 22
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if scheme == .dark {
            content.overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color(red: 0x1A / 255, green: 0x24 / 255, blue: 0x38 / 255), lineWidth: 1))
        } else {
            content.compositingGroup().shadow(color: Color(red: 0, green: 47 / 255, blue: 167 / 255).opacity(0.22), radius: 12, y: 8)
        }
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Palette.card, in: .rect(cornerRadius: 22))
            .modifier(CardShadow())
    }

    func barBackground() -> some View {
        padding(.horizontal, Space.side)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Palette.background.ignoresSafeArea(edges: .bottom))
    }
}

/// Hangul words remain intact when Dynamic Type changes the available line width.
struct KoreanText: View {
    let text: String
    var alignment: HorizontalAlignment = .leading
    let emphasizedWords: Set<String>

    init(_ text: String, alignment: HorizontalAlignment = .leading, emphasizedWords: Set<String> = []) {
        self.text = text
        self.alignment = alignment
        self.emphasizedWords = emphasizedWords
    }

    var body: some View {
        WordFlow(alignment: alignment) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                let token = String(word)
                if emphasizedWords.contains(token) {
                    Text(token).font(TextStyle.bodyBold).foregroundStyle(Palette.accent).fixedSize()
                } else {
                    Text(token).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct WordFlow: Layout {
    var alignment: HorizontalAlignment
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (alignment == .center ? max(0, (bounds.width - row.width) / 2) : 0)
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + 4
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var output: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let gap: CGFloat = row.indices.isEmpty ? 0 : 4
            if !row.indices.isEmpty && row.width + gap + size.width > width {
                output.append(row)
                row = Row(y: row.y + row.height + 3)
            }
            row.width += (row.indices.isEmpty ? 0 : 4) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { output.append(row) }
        return output
    }
}

struct ScreenHeading: View {
    let title: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(title).fixedSize()
            KoreanText(title == "무한끝말잇기" ? "무한 끝말잇기" : title)
        }
        .font(TextStyle.largeTitle)
        .clearsWallpaper()
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(title)
    }
}

struct SheetFrame<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.block) {
                ScreenHeading(title: title)
                content
            }
            .padding(.horizontal, Space.side)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button("닫기") { dismiss() }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("close-\(title)")
                .barBackground()
        }
        .foregroundStyle(Palette.ink)
        .jamoWallpaper()
    }
}
