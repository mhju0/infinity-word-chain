import SwiftUI
import UIKit

/// Inherited Infinity Chosung color system.
/// Blues keep Klein's hue; where a P3 value was specified it is used on wide-gamut screens.
enum Palette {
    static let background = dynamic(light: .hex(0xF2F5FB), dark: .hex(0x080F1C))
    static let card = dynamic(light: .hex(0xFFFFFF), dark: .hex(0x11192A))
    static let line = dynamic(light: .hex(0xDCE3F0), dark: .hex(0x222E45))
    static let ink = dynamic(light: .hex(0x101A2A), dark: .hex(0xE9EEF6))
    static let muted = dynamic(light: .hex(0x525E75), dark: .hex(0xC7D1E5))
    /// 초성, count and accent text.
    static let accent = dynamic(light: .p3(0.0034, 0.1266, 0.6997), dark: .p3(0.4429, 0.5991, 0.9966))
    /// Filled buttons (white label).
    static let fill = dynamic(light: .p3(0.0034, 0.1266, 0.6997), dark: .p3(0.1987, 0.3816, 0.9592))
    static let onFill = Color.white
    static let neon = dynamic(light: .hex(0x337DCA), dark: .p3(0.5910, 0.7118, 0.9973))
    static let correct = dynamic(light: .hex(0x12C972), dark: .hex(0x2FE58C))
    static let wrong = dynamic(light: .hex(0xE5364D), dark: .hex(0xFF5C78))
    static let destructiveText = dynamic(light: .hex(0xBF203B), dark: .hex(0xFF5C78))
    /// The final five seconds use the inherited urgency color.
    static let hurry = dynamic(light: .hex(0x9E4500), dark: .hex(0xFC9F2A))
    static let hurryWash = dynamic(light: UIColor(red: 1, green: 170 / 255, blue: 30 / 255, alpha: 0.38),
                                   dark: UIColor(red: 252 / 255, green: 159 / 255, blue: 42 / 255, alpha: 0.26))
    static let wallpaper = dynamic(light: .hex(0xE0E8F7), dark: .hex(0x131E32))
    static let scrim = dynamic(light: UIColor(red: 10 / 255, green: 18 / 255, blue: 35 / 255, alpha: 0.38), dark: UIColor(white: 0, alpha: 0.55))

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

private extension UIColor {
    static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(displayP3Red: r, green: g, blue: b, alpha: 1)
    }
}

/// Inherited screen and block spacing.
/// Mockups used 16 px at about 0.72× real size.
enum Space {
    static let block: CGFloat = 22
    /// Screen side margin.
    static let side: CGFloat = 22
}

extension Font {
    /// Pretendard for the whole app; scales with Dynamic Type relative to `style`.
    static func pretendard(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(pretendardName(weight), size: size, relativeTo: style)
    }

    /// Fixed size for the match-start countdown.
    static func pretendardFixed(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom(pretendardName(weight), fixedSize: size)
    }

    static func pretendardName(_ weight: Font.Weight) -> String {
        switch weight {
        case .black: "Pretendard-Black"
        case .heavy: "Pretendard-ExtraBold"
        case .bold: "Pretendard-Bold"
        case .semibold: "Pretendard-SemiBold"
        default: "Pretendard-Regular"
        }
    }
}

/// Type steps used across screens (mockup px × ~1.2, then rounded to iOS-like sizes).
enum TextStyle {
    static let body = Font.pretendard(17)
    static let bodyBold = Font.pretendard(17, .bold)
    static let small = Font.pretendard(14, relativeTo: .footnote)
    static let smallBold = Font.pretendard(14, .bold, relativeTo: .footnote)
    static let barTitle = Font.pretendard(20, .heavy, relativeTo: .headline)
    static let largeTitle = Font.pretendard(28, .heavy, relativeTo: .title)
    static let sheetTitle = Font.pretendard(21, .bold, relativeTo: .title3)
    static let button = Font.pretendard(18, .heavy, relativeTo: .headline)
    static let buttonSmall = Font.pretendard(15, .bold, relativeTo: .subheadline)
    static let chip = Font.pretendard(15, .semibold, relativeTo: .subheadline)
    static let section = Font.pretendard(14, .bold, relativeTo: .footnote)
    static let bigNumber = Font.pretendard(56, .black, relativeTo: .largeTitle)
}

enum Theme: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "시스템"
        case .light: "라이트"
        case .dark: "다크"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
