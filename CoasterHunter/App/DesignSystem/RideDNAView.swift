import SwiftUI
import CoasterHunterCore

/// The signature graphic: one lap's vertical-g trace over time.
///
/// Airtime is shaded rather than merely plotted, because "where was I weightless"
/// is the question a rider actually asks of this chart. Inversions are marked on
/// the curve so the shape and the count agree with each other.
public struct RideDNAView: View {
    @Environment(\.colorScheme) private var scheme

    private let trace: RideTrace
    private let airtimeThreshold: Double
    private let showsAxis: Bool

    public init(trace: RideTrace, airtimeThreshold: Double = 0.5, showsAxis: Bool = true) {
        self.trace = trace
        self.airtimeThreshold = airtimeThreshold
        self.showsAxis = showsAxis
    }

    /// Fixed bounds so two traces can be compared by eye. A curve that clips is
    /// less misleading than one drawn to a different scale each time.
    private let range: ClosedRange<Double> = -1.5...5.0

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = plotPoints(in: size)

            ZStack(alignment: .topLeading) {
                airtimeBands(points: points, size: size)
                if showsAxis { referenceLines(size: size) }
                curve(points: points)
                inversionMarkers(points: points)
            }
        }
        .frame(height: 96)
        .accessibilityLabel("G-force trace")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Layers

    private func airtimeBands(points: [CGPoint], size: CGSize) -> some View {
        Path { path in
            for run in airtimeRuns() {
                let x0 = x(for: run.lowerBound, in: size)
                let x1 = x(for: run.upperBound, in: size)
                path.addRect(CGRect(x: x0, y: 0, width: max(1.5, x1 - x0), height: size.height))
            }
        }
        .fill(Palette.airtime.opacity(0.16))
    }

    private func referenceLines(size: CGSize) -> some View {
        ZStack {
            // 1 g — the ride's resting state.
            Path { path in
                let y = y(forG: 1, in: size)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(Palette.line(scheme), lineWidth: 1)

            // 0 g — the line airtime lives below.
            Path { path in
                let y = y(forG: 0, in: size)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(Palette.airtime.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
    }

    private func curve(points: [CGPoint]) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(
            Palette.gForce,
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func inversionMarkers(points: [CGPoint]) -> some View {
        ForEach(Array(inversionIndices().enumerated()), id: \.offset) { _, index in
            if index < points.count {
                Circle()
                    .fill(Palette.track)
                    .frame(width: 5, height: 5)
                    .position(points[index])
            }
        }
    }

    // MARK: Geometry

    private var displayTrace: RideTrace {
        trace.samples.count > 400 ? trace.downsampled(to: 400) : trace
    }

    private func plotPoints(in size: CGSize) -> [CGPoint] {
        let samples = displayTrace.samples
        guard samples.count > 1 else { return [] }
        return samples.map {
            CGPoint(x: x(for: $0.time, in: size), y: y(forG: $0.verticalG, in: size))
        }
    }

    private func x(for time: Double, in size: CGSize) -> CGFloat {
        guard let first = trace.samples.first, trace.duration > 0 else { return 0 }
        return CGFloat((time - first.time) / trace.duration) * size.width
    }

    private func y(forG value: Double, in size: CGSize) -> CGFloat {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        let fraction = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return size.height * (1 - CGFloat(fraction))
    }

    // MARK: Derived

    private func airtimeRuns() -> [ClosedRange<Double>] {
        var runs: [ClosedRange<Double>] = []
        var start: Double?

        for sample in displayTrace.samples {
            if sample.verticalG < airtimeThreshold, start == nil {
                start = sample.time
            } else if sample.verticalG >= airtimeThreshold, let began = start {
                runs.append(began...sample.time)
                start = nil
            }
        }
        if let began = start, let last = displayTrace.samples.last, last.time > began {
            runs.append(began...last.time)
        }
        return runs
    }

    /// Midpoint of each period spent upside down, as an index into the plot.
    private func inversionIndices() -> [Int] {
        let samples = displayTrace.samples
        var indices: [Int] = []
        var start: Int?

        for (index, sample) in samples.enumerated() {
            let inverted = sample.tiltDegrees >= 120
            if inverted, start == nil {
                start = index
            } else if !inverted, let began = start {
                indices.append((began + index) / 2)
                start = nil
            }
        }
        return indices
    }

    private var accessibilitySummary: String {
        guard let metrics = MetricsCalculator.metrics(for: trace) else { return "No data" }
        return "Peak \(metrics.peakVerticalG) g, "
            + "\(metrics.sustainedAirtimeSeconds) seconds of airtime, "
            + "\(metrics.inversions) inversions"
    }
}

/// Key for the trace, so the shaded bands are explained rather than decorative.
public struct RideDNALegend: View {
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            item(color: Palette.airtime, label: "airtime")
            item(color: Palette.gForce, label: "g-load")
            item(color: Palette.track, label: "inversion")
        }
    }

    private func item(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.inkTertiary(scheme))
        }
    }
}
