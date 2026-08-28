#if !SHIM_TESTS
@testable import CoasterHunterCore
#endif
import Foundation

/// Synthetic traces with known, deliberate physics.
///
/// These are not recordings — they are constructed so every expected value is
/// arithmetic rather than a guess, which is what makes the assertions meaningful
/// before real rides have been recorded. Once there are traces from an actual
/// watch they should be added alongside these, not instead of them: a fixture
/// with a known answer catches regressions that a recording cannot.
enum TraceFixtures {

    static let sampleRate: Double = 100

    /// Steady 1 g. A trace that never leaves the station.
    static func flat(duration: Double = 10) -> RideTrace {
        build(duration: duration) { _ in (1.0, 0.0, 0.0, 0.0) }
    }

    /// An airtime hill machine: three clean floater moments of known length,
    /// separated by positive-g pullouts. No inversions.
    ///
    /// Airtime windows: 10.0–11.2, 20.0–21.0, 30.0–30.6 → 2.8 s total,
    /// all three long enough to count as sustained.
    static func airtimeMachine() -> RideTrace {
        let windows: [(start: Double, end: Double)] = [
            (10.0, 11.2), (20.0, 21.0), (30.0, 30.6),
        ]
        return build(duration: 40) { t in
            for window in windows where t >= window.start && t < window.end {
                return (-0.3, 0.0, 0.0, 0.0)   // ejector airtime
            }
            // Pullouts either side of each hill.
            for window in windows {
                if abs(t - (window.start - 1.5)) < 0.5 { return (3.8, 0.2, 0.0, 0.0) }
            }
            return (1.0, 0.0, 0.0, 0.0)
        }
    }

    /// A looper: four inversions of known duration, plus heavy positive g.
    ///
    /// Inversion windows are 1.0 s each and 4 s apart, comfortably clear of both
    /// the minimum duration and the minimum gap.
    static func looper() -> RideTrace {
        let inversions: [(start: Double, end: Double)] = [
            (10.0, 11.0), (15.0, 16.0), (20.0, 21.0), (25.0, 26.0),
        ]
        return build(duration: 40) { t in
            for window in inversions where t >= window.start && t < window.end {
                // Upside down: gravity points along -Y in the device frame.
                return (2.5, 0.4, 0.0, -1.0)
            }
            // Real track between inversions is never a flat load — it rises
            // and falls continuously, which is what keeps a capture alive.
            return (1.2 + 0.9 * sin(t * 1.1), 0.1 + 0.4 * sin(t * 0.6), 0.0, 1.0)
        }
    }

    /// Smooth ride: no high-frequency content at all.
    static func smooth() -> RideTrace {
        build(duration: 30) { t in (1.0 + 0.6 * sin(t * 0.7), 0.2 * sin(t * 0.4), 0, 0) }
    }

    /// Rough ride: the same shape with a 12 Hz rattle laid over it.
    static func rough(amplitude: Double = 0.9) -> RideTrace {
        build(duration: 30) { t in
            (1.0 + 0.6 * sin(t * 0.7) + amplitude * sin(t * 2 * .pi * 12),
             0.2 * sin(t * 0.4), 0, 0)
        }
    }

    /// A brief dip below the airtime threshold — a pothole, not airtime.
    static func shortBump() -> RideTrace {
        build(duration: 10) { t in
            (t >= 5.0 && t < 5.15) ? (0.2, 0, 0, 0) : (1.0, 0, 0, 0)
        }
    }

    /// The same ride run slower, as a full train on a cold morning would be.
    static func timeStretched(_ trace: RideTrace, by factor: Double) -> RideTrace {
        RideTrace(
            samples: trace.samples.map {
                MotionSample(
                    time: $0.time * factor, verticalG: $0.verticalG,
                    lateralG: $0.lateralG, longitudinalG: $0.longitudinalG,
                    gravityX: $0.gravityX, gravityY: $0.gravityY, gravityZ: $0.gravityZ)
            },
            sampleRateHz: trace.sampleRateHz / factor,
            startedAt: trace.startedAt)
    }

    /// - Parameter shape: time → (verticalG, lateralG, longitudinalG, gravityY)
    ///   where gravityY is +1 upright and -1 inverted.
    private static func build(
        duration: Double,
        shape: (Double) -> (Double, Double, Double, Double)
    ) -> RideTrace {
        let count = Int(duration * sampleRate)
        var samples: [MotionSample] = []
        samples.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let (vertical, lateral, longitudinal, gravityY) = shape(t)
            samples.append(MotionSample(
                time: t, verticalG: vertical, lateralG: lateral,
                longitudinalG: longitudinal,
                gravityX: 0, gravityY: gravityY == 0 ? 1 : gravityY, gravityZ: 0))
        }
        return RideTrace(samples: samples, sampleRateHz: sampleRate)
    }
}
