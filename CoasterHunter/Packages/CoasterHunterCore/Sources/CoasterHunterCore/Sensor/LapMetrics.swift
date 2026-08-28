import Foundation

/// What the watch measured, reduced to the numbers a rider actually cares about.
public struct LapMetrics: Codable, Hashable, Sendable {
    public let durationSeconds: Double

    /// Highest sustained vertical load, in g.
    public let peakVerticalG: Double
    /// Most negative vertical load — the best floater or ejector moment.
    public let minVerticalG: Double
    public let peakLateralG: Double
    public let peakLongitudinalG: Double

    /// Total time below the airtime threshold.
    public let airtimeSeconds: Double
    /// Airtime in runs long enough to actually feel, which is what people mean.
    public let sustainedAirtimeSeconds: Double
    /// Number of distinct sustained airtime moments.
    public let airtimeMoments: Int

    public let inversions: Int

    /// Rattle, 0–10. Low is smooth; high is the thing people complain about.
    public let roughnessIndex: Double

    /// Composite intensity, 0–100, so different rides can be compared.
    public let rideScore: Int

    public init(
        durationSeconds: Double, peakVerticalG: Double, minVerticalG: Double,
        peakLateralG: Double, peakLongitudinalG: Double,
        airtimeSeconds: Double, sustainedAirtimeSeconds: Double, airtimeMoments: Int,
        inversions: Int, roughnessIndex: Double, rideScore: Int
    ) {
        self.durationSeconds = durationSeconds
        self.peakVerticalG = peakVerticalG
        self.minVerticalG = minVerticalG
        self.peakLateralG = peakLateralG
        self.peakLongitudinalG = peakLongitudinalG
        self.airtimeSeconds = airtimeSeconds
        self.sustainedAirtimeSeconds = sustainedAirtimeSeconds
        self.airtimeMoments = airtimeMoments
        self.inversions = inversions
        self.roughnessIndex = roughnessIndex
        self.rideScore = rideScore
    }
}

/// Derives `LapMetrics` from a raw trace.
///
/// The thresholds below are the arguable part, so they are named constants with
/// stated reasoning rather than magic numbers buried in the maths. They should
/// be revisited once there are real traces from real rides to calibrate against.
public enum MetricsCalculator {

    public struct Thresholds: Sendable {
        /// Below this vertical load the rider is light in the restraint. 0.5 g is
        /// the figure the enthusiast community already uses informally.
        public var airtimeG: Double = 0.5
        /// A dip shorter than this is a bump, not airtime.
        public var minimumAirtimeRun: Double = 0.4
        /// Beyond this tilt the rider is upside down.
        public var invertedTiltDegrees: Double = 120
        /// An inversion has to last this long — otherwise a sharp banked turn
        /// that briefly clips the threshold would be counted.
        public var minimumInversionDuration: Double = 0.25
        /// Two inversions closer than this are one wobbly inversion.
        public var minimumInversionGap: Double = 0.4
        /// Peak g is taken as this percentile, not the outright maximum, because
        /// a single spike is usually the rider's arm hitting the restraint.
        public var peakPercentile: Double = 0.99

        public init() {}
    }

    public static func metrics(
        for trace: RideTrace,
        thresholds: Thresholds = Thresholds()
    ) -> LapMetrics? {
        guard !trace.isEmpty else { return nil }
        let samples = trace.samples

        let vertical = samples.map(\.verticalG)
        let peakVertical = percentile(vertical, thresholds.peakPercentile)
        let minVertical = percentile(vertical, 1 - thresholds.peakPercentile)
        let peakLateral = percentile(samples.map { abs($0.lateralG) }, thresholds.peakPercentile)
        let peakLongitudinal = percentile(
            samples.map { abs($0.longitudinalG) }, thresholds.peakPercentile)

        let airtime = airtimeRuns(samples, thresholds: thresholds)
        let sustained = airtime.filter { $0 >= thresholds.minimumAirtimeRun }

        let inversions = countInversions(samples, thresholds: thresholds)
        let roughness = roughnessIndex(samples)

        let score = rideScore(
            peakVerticalG: peakVertical,
            minVerticalG: minVertical,
            peakLateralG: peakLateral,
            sustainedAirtime: sustained.reduce(0, +),
            inversions: inversions,
            duration: trace.duration
        )

        return LapMetrics(
            durationSeconds: round(trace.duration * 10) / 10,
            peakVerticalG: round(peakVertical * 10) / 10,
            minVerticalG: round(minVertical * 10) / 10,
            peakLateralG: round(peakLateral * 10) / 10,
            peakLongitudinalG: round(peakLongitudinal * 10) / 10,
            airtimeSeconds: round(airtime.reduce(0, +) * 10) / 10,
            sustainedAirtimeSeconds: round(sustained.reduce(0, +) * 10) / 10,
            airtimeMoments: sustained.count,
            inversions: inversions,
            roughnessIndex: round(roughness * 10) / 10,
            rideScore: score
        )
    }

    // ----------------------------------------------------------- components ---

    /// Durations of every contiguous stretch spent below the airtime threshold.
    static func airtimeRuns(
        _ samples: [MotionSample], thresholds: Thresholds
    ) -> [Double] {
        var runs: [Double] = []
        var runStart: Double?

        for sample in samples {
            let floating = sample.verticalG < thresholds.airtimeG
            if floating, runStart == nil {
                runStart = sample.time
            } else if !floating, let start = runStart {
                runs.append(sample.time - start)
                runStart = nil
            }
        }
        if let start = runStart, let last = samples.last {
            runs.append(last.time - start)
        }
        return runs.filter { $0 > 0 }
    }

    /// Count of periods spent upside down.
    ///
    /// Uses the gravity vector's tilt rather than integrating gyro rates, which
    /// drift over a 90-second ride. Requires both a minimum duration and a
    /// minimum gap so a heartline roll counts once, not three times.
    static func countInversions(
        _ samples: [MotionSample], thresholds: Thresholds
    ) -> Int {
        var count = 0
        var invertedSince: Double?
        var lastInversionEnded: Double = -.infinity

        func close(at time: Double) {
            guard let since = invertedSince else { return }
            let duration = time - since
            let gap = since - lastInversionEnded
            if duration >= thresholds.minimumInversionDuration,
               gap >= thresholds.minimumInversionGap {
                count += 1
                lastInversionEnded = time
            }
            invertedSince = nil
        }

        for sample in samples {
            let inverted = sample.tiltDegrees >= thresholds.invertedTiltDegrees
            if inverted, invertedSince == nil {
                invertedSince = sample.time
            } else if !inverted {
                close(at: sample.time)
            }
        }
        if let last = samples.last { close(at: last.time) }
        return count
    }

    /// Rattle, expressed 0–10.
    ///
    /// Jerk — the rate of change of acceleration — is where roughness lives.
    /// A band-pass keeps 4–20 Hz: below that is the ride's intended shape, above
    /// it is sensor noise and the watch moving on the wrist.
    static func roughnessIndex(_ samples: [MotionSample]) -> Double {
        guard samples.count > 10 else { return 0 }

        var jerk: [Double] = []
        jerk.reserveCapacity(samples.count - 1)
        for i in 1..<samples.count {
            let dt = samples[i].time - samples[i - 1].time
            guard dt > 0 else { continue }
            jerk.append((samples[i].magnitudeG - samples[i - 1].magnitudeG) / dt)
        }
        guard jerk.count > 4 else { return 0 }

        let sampleRate = Double(samples.count - 1)
            / max(0.001, samples[samples.count - 1].time - samples[0].time)
        let filtered = bandPass(jerk, sampleRate: sampleRate, low: 4, high: 20)

        let meanSquare = filtered.reduce(0) { $0 + $1 * $1 } / Double(filtered.count)
        let rms = meanSquare.squareRoot()

        // Scaled so a modern smooth steel coaster lands near 1–2 and a notoriously
        // rough old woodie lands near 7–9. Needs recalibrating against real traces.
        let scaled = rms / 12.0
        return max(0, min(10, scaled))
    }

    /// Composite intensity, 0–100.
    ///
    /// Weighted so airtime matters most — it is what enthusiasts chase, and a
    /// score dominated by peak g would just rank rides by how hard they pull
    /// through the bottom of a drop.
    static func rideScore(
        peakVerticalG: Double, minVerticalG: Double, peakLateralG: Double,
        sustainedAirtime: Double, inversions: Int, duration: Double
    ) -> Int {
        let airtimeScore = min(1, sustainedAirtime / 8.0) * 35
        let ejectorScore = min(1, max(0, -minVerticalG + 0.5) / 1.5) * 20
        let positiveScore = min(1, max(0, peakVerticalG - 1) / 4.0) * 20
        let lateralScore = min(1, peakLateralG / 2.5) * 10
        let inversionScore = min(1, Double(inversions) / 7.0) * 10
        let lengthScore = min(1, duration / 150.0) * 5

        let total = airtimeScore + ejectorScore + positiveScore
            + lateralScore + inversionScore + lengthScore
        return Int(max(0, min(100, total.rounded())))
    }

    // ---------------------------------------------------------------- maths ---

    /// Value at a percentile, 0...1. Guards against single-sample spikes.
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = max(0, min(Double(sorted.count - 1), p * Double(sorted.count - 1)))
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    /// Two cascaded one-pole filters — a high-pass then a low-pass.
    ///
    /// Deliberately simple: a steeper filter would need coefficients tuned
    /// against real traces, which do not exist yet, and a gentle roll-off is
    /// easier to reason about when the numbers look wrong.
    static func bandPass(
        _ input: [Double], sampleRate: Double, low: Double, high: Double
    ) -> [Double] {
        guard sampleRate > 0, input.count > 2 else { return input }

        let dt = 1.0 / sampleRate

        // High-pass at `low` Hz.
        let rcHigh = 1.0 / (2 * .pi * low)
        let alphaHigh = rcHigh / (rcHigh + dt)
        var highPassed = [Double](repeating: 0, count: input.count)
        for i in 1..<input.count {
            highPassed[i] = alphaHigh * (highPassed[i - 1] + input[i] - input[i - 1])
        }

        // Low-pass at `high` Hz.
        let rcLow = 1.0 / (2 * .pi * high)
        let alphaLow = dt / (rcLow + dt)
        var output = [Double](repeating: 0, count: input.count)
        output[0] = highPassed[0]
        for i in 1..<highPassed.count {
            output[i] = output[i - 1] + alphaLow * (highPassed[i] - output[i - 1])
        }
        return output
    }
}
