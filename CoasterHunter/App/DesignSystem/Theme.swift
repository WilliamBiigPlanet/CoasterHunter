import SwiftUI

/// The colour system, taken from the reference set.
///
/// Two complete palettes rather than one inverted: the dark ground is a slightly
/// blue near-black so the mesh gradients stay saturated against it, and the light
/// ground is a warm-neutral grey rather than white, so white cards still read as
/// cards sitting on something.
public enum Palette {

    // MARK: Surfaces

    public static func ground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0A0A0C) : Color(hex: 0xECECEE)
    }

    public static func groundRaised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x101014) : Color(hex: 0xE5E5E8)
    }

    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x16161A) : Color(hex: 0xFFFFFF)
    }

    public static func surfaceMuted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1D1D22) : Color(hex: 0xF6F6F8)
    }

    public static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x26262E) : Color(hex: 0xDCDCE1)
    }

    // MARK: Text

    public static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF4F4F6) : Color(hex: 0x0D0D11)
    }

    public static func inkSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x9C9CA8) : Color(hex: 0x5A5A66)
    }

    public static func inkTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x61616D) : Color(hex: 0x8C8C98)
    }

    /// Fine dot grid that sits behind everything.
    public static func dot(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.055)
    }

    // MARK: Accents
    //
    // These stay identical in both themes — they are the mesh gradient colours
    // and they hold up on either ground. `airtimeText` is the exception: acid
    // green fails contrast as text on white, so it gets a darker value.

    public static let gForce = Color(hex: 0xFF2E8B)
    public static let violet = Color(hex: 0x7A3CF0)
    public static let track = Color(hex: 0x2E52FF)
    public static let airtime = Color(hex: 0x48E06A)
    public static let heat = Color(hex: 0xFF7A1A)

    public static func airtimeText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x48E06A) : Color(hex: 0x1E9E45)
    }

    // MARK: Semantic
    //
    // Kept separate from the accents on purpose. A warning must not be
    // confusable with a brand colour.

    public static let warning = Color(hex: 0xFFB020)
    public static let critical = Color(hex: 0xFF4A3D)
}

/// The gradient tiles that carry the one number that matters on each screen.
public enum MeshGradient {
    public static let thrill = LinearGradient(
        colors: [Color(hex: 0xFF2E8B), Color(hex: 0x7A3CF0), Color(hex: 0x2E52FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    public static let air = LinearGradient(
        colors: [Color(hex: 0xB9F227), Color(hex: 0x48E06A), Color(hex: 0x12A94A)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    public static let heat = LinearGradient(
        colors: [Color(hex: 0xFFB020), Color(hex: 0xFF7A1A), Color(hex: 0xFF2E8B)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Type scale.
///
/// Outfit for display and numerals, Manrope for reading. Both are bundled under
/// the SIL Open Font Licence. `fallback` keeps the app legible if a face fails
/// to register rather than silently dropping to a face that ruins the layout.
public enum Typography {
    private static let display = "Outfit"
    private static let body = "Manrope"

    /// The single hero number on a screen. Light weight, tight tracking.
    public static func hero(_ size: CGFloat = 52) -> Font {
        .custom(display, size: size, relativeTo: .largeTitle).weight(.ultraLight)
    }

    public static func statValue(_ size: CGFloat = 26) -> Font {
        .custom(display, size: size, relativeTo: .title2).weight(.thin)
    }

    public static var screenTitle: Font {
        .custom(display, size: 20, relativeTo: .title3).weight(.medium)
    }

    public static var rowTitle: Font {
        .custom(body, size: 15, relativeTo: .body).weight(.semibold)
    }

    public static var bodyText: Font {
        .custom(body, size: 15, relativeTo: .body)
    }

    /// Small uppercase key, with the letter-spacing applied at the call site
    /// via `.kerning` — SwiftUI has no tracking on Font itself.
    public static var label: Font {
        .custom(body, size: 11, relativeTo: .caption).weight(.semibold)
    }

    public static var caption: Font {
        .custom(body, size: 12, relativeTo: .caption)
    }
}

public enum Metrics {
    public static let cardRadius: CGFloat = 22
    public static let tileRadius: CGFloat = 20
    public static let heroRadius: CGFloat = 26
    public static let gutter: CGFloat = 14
    public static let tileGap: CGFloat = 9
    public static let dotGridSpacing: CGFloat = 16
}

extension Color {
    /// 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
