import Foundation

/// A reference profile for one attraction, built by averaging confirmed laps.
public struct RideTemplate: Codable, Hashable, Sendable {
    public let attractionID: String
    /// Vertical-g envelope resampled onto a fixed grid, so traces of slightly
    /// different lengths are comparable.
    public let profile: [Double]
    /// How many confirmed laps went into it. Confidence rises with this.
    public let lapCount: Int
    public let meanDuration: Double

    public init(attractionID: String, profile: [Double], lapCount: Int, meanDuration: Double) {
        self.attractionID = attractionID
        self.profile = profile
        self.lapCount = lapCount
        self.meanDuration = meanDuration
    }
}

public struct TraceMatch: Sendable {
    public let attractionID: String
    /// 0–1. Above `TraceMatcher.autoLogThreshold` we log without asking.
    public let confidence: Double
}

/// Identifies which ride a trace came from.
///
/// Trains do not run at identical speeds — a full train is slower than an empty
/// one, and a wet track slower still — so the comparison has to tolerate the
/// time axis stretching. That is what dynamic time warping is for.
///
/// The template library starts empty. Until it has real laps in it, matching is
/// off and the watch asks the rider to confirm; every confirmation feeds a lap
/// back into the template.
public enum TraceMatcher {

    /// Resolution of the normalised profile. 128 points over a 90-second ride is
    /// roughly one point per 0.7 s — enough to capture each hill, cheap to warp.
    public static let profileLength = 128

    /// Log automatically at or above this. Below it, ask.
    public static let autoLogThreshold = 0.82

    /// Duration must be within this fraction of the template's mean, or it is
    /// not the same ride however similar the shape looks.
    public static let durationTolerance = 0.35

    /// Resample the vertical-g envelope onto a fixed grid and normalise it, so
    /// only the shape is compared and not the absolute intensity.
    public static func profile(from trace: RideTrace, length: Int = profileLength) -> [Double] {
        guard !trace.isEmpty, length > 1 else { return [] }

        let samples = trace.samples
        let start = samples[0].time
        let span = max(0.001, samples[samples.count - 1].time - start)

        var resampled = [Double](repeating: 0, count: length)
        var cursor = 0

        for i in 0..<length {
            let target = start + span * Double(i) / Double(length - 1)
            while cursor < samples.count - 2, samples[cursor + 1].time < target {
                cursor += 1
            }
            let a = samples[cursor]
            let b = samples[min(cursor + 1, samples.count - 1)]
            let gap = b.time - a.time
            let t = gap > 0 ? (target - a.time) / gap : 0
            resampled[i] = a.verticalG + (b.verticalG - a.verticalG) * min(1, max(0, t))
        }

        return normalise(resampled)
    }

    /// Zero mean, unit standard deviation. Removes the effect of how tightly the
    /// watch is strapped on and where on the wrist it sits.
    static func normalise(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return values }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let sd = variance.squareRoot()
        guard sd > 0.0001 else { return values.map { _ in 0 } }
        return values.map { ($0 - mean) / sd }
    }

    /// Dynamic time warping distance with a Sakoe–Chiba band.
    ///
    /// The band caps how far the alignment may drift, which both speeds it up
    /// and stops a wildly different ride being warped into a false match.
    public static func warpDistance(_ a: [Double], _ b: [Double], bandFraction: Double = 0.2) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return .infinity }

        let n = a.count
        let m = b.count
        let band = max(abs(n - m) + 1, Int(Double(max(n, m)) * bandFraction))

        var previous = [Double](repeating: .infinity, count: m + 1)
        var current = [Double](repeating: .infinity, count: m + 1)
        previous[0] = 0

        for i in 1...n {
            current[0] = .infinity
            let lower = max(1, i - band)
            let upper = min(m, i + band)
            if lower > 1 { current[lower - 1] = .infinity }

            for j in lower...upper {
                let cost = abs(a[i - 1] - b[j - 1])
                current[j] = cost + min(previous[j], min(current[j - 1], previous[j - 1]))
            }
            swap(&previous, &current)
            for j in 0...m { current[j] = .infinity }
        }

        let total = previous[m]
        return total.isFinite ? total / Double(n + m) : .infinity
    }

    /// Best matching template for a captured trace.
    ///
    /// - Parameter candidates: templates for attractions at the park the rider
    ///   is currently checked into. Scoping by park is what makes this tractable —
    ///   comparing against every coaster on earth would be both slow and wrong,
    ///   because clone models are genuinely near-identical.
    public static func match(
        trace: RideTrace,
        candidates: [RideTemplate]
    ) -> TraceMatch? {
        guard !trace.isEmpty, !candidates.isEmpty else { return nil }

        let observed = profile(from: trace)
        let duration = trace.duration
        var best: TraceMatch?

        for template in candidates {
            guard template.lapCount > 0, !template.profile.isEmpty else { continue }

            // Duration gate first — it is cheap and rules out most candidates.
            let ratio = abs(duration - template.meanDuration) / max(1, template.meanDuration)
            if ratio > durationTolerance { continue }

            let distance = warpDistance(observed, template.profile)
            guard distance.isFinite else { continue }

            // Map distance to a 0–1 confidence. A distance of 0 is identical;
            // beyond about 1.0 the shapes have nothing in common.
            var confidence = max(0, 1 - distance)

            // A template built from two laps is not yet trustworthy.
            let maturity = min(1, Double(template.lapCount) / 8.0)
            confidence *= (0.6 + 0.4 * maturity)

            if best == nil || confidence > best!.confidence {
                best = TraceMatch(attractionID: template.attractionID, confidence: confidence)
            }
        }
        return best
    }

    /// Fold a newly confirmed lap into a template.
    public static func updated(
        template: RideTemplate?, with trace: RideTrace, attractionID: String
    ) -> RideTemplate {
        let observed = profile(from: trace)

        guard let template, template.lapCount > 0, template.profile.count == observed.count else {
            return RideTemplate(
                attractionID: attractionID, profile: observed,
                lapCount: 1, meanDuration: trace.duration)
        }

        let n = Double(template.lapCount)
        let blended = zip(template.profile, observed).map { ($0 * n + $1) / (n + 1) }
        let duration = (template.meanDuration * n + trace.duration) / (n + 1)

        return RideTemplate(
            attractionID: attractionID, profile: blended,
            lapCount: template.lapCount + 1, meanDuration: duration)
    }
}
