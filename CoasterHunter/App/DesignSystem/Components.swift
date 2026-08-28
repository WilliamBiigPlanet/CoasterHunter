import SwiftUI

// MARK: - Ground

/// The fine dot grid the whole app sits on.
///
/// Drawn with Canvas rather than a tiled image so it stays crisp at any scale
/// and re-themes instantly without shipping two assets.
public struct DotGridBackground: View {
    @Environment(\.colorScheme) private var scheme
    public var spacing: CGFloat = Metrics.dotGridSpacing

    public init(spacing: CGFloat = Metrics.dotGridSpacing) {
        self.spacing = spacing
    }

    public var body: some View {
        Palette.ground(scheme)
            .overlay {
                Canvas { context, size in
                    let dot = Palette.dot(scheme)
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = 0
                        while x < size.width {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                                with: .color(dot))
                            x += spacing
                        }
                        y += spacing
                    }
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }
}

// MARK: - Surfaces

/// The standard card: a heavily-rounded rectangle with a hairline border.
///
/// A border rather than a shadow, because on the near-black ground a shadow is
/// invisible and the edge is what separates one card from the next.
public struct SquircleCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(
        radius: CGFloat = Metrics.cardRadius,
        padding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface(scheme), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.line(scheme), lineWidth: 1)
            }
    }
}

/// The saturated tile that carries the one number that matters.
public struct MeshHeroTile<Content: View>: View {
    private let gradient: LinearGradient
    private let content: Content

    public init(gradient: LinearGradient, @ViewBuilder content: () -> Content) {
        self.gradient = gradient
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                gradient.overlay(GrainOverlay())
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous))
            .foregroundStyle(.white)
    }
}

/// Fine noise over the gradients. Flat gradients on an OLED panel band visibly;
/// a little grain hides it and matches the reference set's texture.
struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 0x5EED)
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = Double.random(in: 0..<size.width, using: &generator)
                let y = Double.random(in: 0..<size.height, using: &generator)
                let alpha = Double.random(in: 0.02..<0.09, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(alpha)))
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

/// Deterministic noise, so the grain does not shimmer on every redraw.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B9 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Numerals

/// The big dotted numeral from the reference set.
///
/// Real dot-matrix glyphs would need a bespoke font; masking the text with a dot
/// pattern gets the same effect from any face, and degrades to plain type if the
/// mask cannot be rendered.
public struct DotMatrixNumeral: View {
    private let text: String
    private let size: CGFloat

    public init(_ text: String, size: CGFloat = 52) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Text(text)
            .font(Typography.hero(size))
            .monospacedDigit()
            .kerning(-size * 0.04)
            .mask(alignment: .topLeading) { DotPattern(spacing: max(2.4, size * 0.07)) }
            .overlay {
                // Keeps the glyph readable at small sizes, where the dots alone
                // start to lose the shape.
                Text(text)
                    .font(Typography.hero(size))
                    .monospacedDigit()
                    .kerning(-size * 0.04)
                    .opacity(0.22)
            }
    }
}

struct DotPattern: View {
    var spacing: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            var y: CGFloat = 0
            while y < canvasSize.height {
                var x: CGFloat = 0
                while x < canvasSize.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: spacing * 0.52, height: spacing * 0.52)),
                        with: .color(.white))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

// MARK: - Small parts

public struct StatTile: View {
    @Environment(\.colorScheme) private var scheme

    private let key: String
    private let value: String
    private let unit: String?
    private let delta: String?
    private let deltaIsGood: Bool

    public init(
        key: String, value: String, unit: String? = nil,
        delta: String? = nil, deltaIsGood: Bool = true
    ) {
        self.key = key
        self.value = value
        self.unit = unit
        self.delta = delta
        self.deltaIsGood = deltaIsGood
    }

    public var body: some View {
        SquircleCard(radius: Metrics.tileRadius, padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.uppercased())
                    .font(Typography.label)
                    .kerning(0.6)
                    .foregroundStyle(Palette.inkTertiary(scheme))

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(Typography.statValue())
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink(scheme))
                    if let unit {
                        Text(unit)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary(scheme))
                    }
                }

                if let delta {
                    Text(delta)
                        .font(Typography.label)
                        .foregroundStyle(deltaIsGood ? Palette.airtimeText(scheme) : Palette.critical)
                }
            }
        }
    }
}

public struct EyebrowLabel: View {
    @Environment(\.colorScheme) private var scheme
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(Typography.label)
            .kerning(1.1)
            .foregroundStyle(Palette.inkTertiary(scheme))
    }
}

/// The circular icon button used in headers.
public struct CircleIconButton: View {
    @Environment(\.colorScheme) private var scheme
    private let systemName: String
    private let action: () -> Void

    public init(systemName: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.inkSecondary(scheme))
                .frame(width: 32, height: 32)
                .background(Palette.surface(scheme), in: Circle())
                .overlay { Circle().strokeBorder(Palette.line(scheme), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// A row in a list of laps or attractions.
public struct AttractionRow: View {
    @Environment(\.colorScheme) private var scheme

    private let name: String
    private let detail: String
    private let accent: Color

    public init(name: String, detail: String, accent: Color) {
        self.name = name
        self.detail = detail
        self.accent = accent
    }

    public var body: some View {
        SquircleCard(radius: 16, padding: 10) {
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(name)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink(scheme))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(detail)
                    .font(Typography.label)
                    .foregroundStyle(Palette.inkTertiary(scheme))
                    .lineLimit(1)
            }
        }
    }
}
