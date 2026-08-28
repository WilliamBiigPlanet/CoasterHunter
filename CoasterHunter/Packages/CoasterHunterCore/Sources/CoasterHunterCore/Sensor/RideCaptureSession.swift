import Foundation

/// The state machine that decides when a ride starts and stops.
///
/// Deliberately free of CoreMotion so it can be driven by fixture samples and
/// tested. The CoreMotion binding on the watch does nothing but feed samples in
/// and act on what comes out — all the judgement lives here.
///
/// The shape of the problem: the watch cannot sample at 100 Hz all day, so it
/// idles at a low rate and only promotes to full rate when something that looks
/// like a ride begins. Getting the promotion wrong in one direction wastes
/// battery; getting it wrong in the other misses the lap entirely, which is
/// worse, so the entry threshold is deliberately generous and the exit is strict.
public final class RideCaptureSession {

    public enum State: Equatable {
        /// In the park, sampling slowly, waiting for something to happen.
        case idle
        /// Something started. Capturing at full rate.
        case capturing
        /// Back to rest for long enough that the ride is over.
        case finished
    }

    public struct Configuration: Sendable {
        /// Deviation from 1 g that suggests a ride rather than walking.
        /// A brisk walk peaks around 1.3 g, so 0.45 clears normal movement.
        public var triggerDeviation: Double = 0.45
        /// Sustained deviation for this long before we believe it.
        public var triggerDuration: Double = 0.8
        /// Back within this of 1 g counts as at rest.
        public var restDeviation: Double = 0.25
        /// At rest for this long means the ride has ended. Long enough to
        /// survive a mid-course brake run, which would otherwise split one lap
        /// into two and double the rider's count. Several Intamin and B&M
        /// layouts hold on the mid-course for five seconds or more, so this sits
        /// above that — at the cost of confirming each lap a few seconds later.
        public var restDuration: Double = 7.0
        /// Shorter than this is not a coaster — it is someone waving their arm.
        public var minimumRideDuration: Double = 12.0
        /// Nothing runs longer than this; if we get here something has gone
        /// wrong and continuing would just drain the battery.
        public var maximumRideDuration: Double = 300.0

        public init() {}
    }

    public private(set) var state: State = .idle
    public private(set) var samples: [MotionSample] = []

    private let configuration: Configuration
    private var aboveThresholdSince: Double?
    private var atRestSince: Double?
    private var captureStart: Double?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feed one sample. Returns the completed trace on the sample that ends a ride.
    @discardableResult
    public func ingest(_ sample: MotionSample) -> RideTrace? {
        let deviation = abs(sample.magnitudeG - 1)

        switch state {
        case .idle:
            if deviation >= configuration.triggerDeviation {
                if aboveThresholdSince == nil { aboveThresholdSince = sample.time }
                if let since = aboveThresholdSince,
                   sample.time - since >= configuration.triggerDuration {
                    beginCapturing(from: since, with: sample)
                }
            } else {
                aboveThresholdSince = nil
            }
            return nil

        case .capturing:
            samples.append(sample)

            if let start = captureStart,
               sample.time - start >= configuration.maximumRideDuration {
                return finish(at: sample.time)
            }

            if deviation <= configuration.restDeviation {
                if atRestSince == nil { atRestSince = sample.time }
                if let since = atRestSince,
                   sample.time - since >= configuration.restDuration {
                    return finish(at: since)
                }
            } else {
                atRestSince = nil
            }
            return nil

        case .finished:
            return nil
        }
    }

    /// Give up on the current capture — the rider cancelled, or we left the park.
    public func reset() {
        state = .idle
        samples = []
        aboveThresholdSince = nil
        atRestSince = nil
        captureStart = nil
    }

    // MARK: Transitions

    private func beginCapturing(from triggerTime: Double, with sample: MotionSample) {
        state = .capturing
        captureStart = triggerTime
        // The lift hill happens before the trigger fires, and it is the most
        // recognisable part of the trace — so the capture is backdated rather
        // than started from the moment we noticed.
        samples = [sample]
        atRestSince = nil
    }

    private func finish(at endTime: Double) -> RideTrace? {
        state = .finished

        let trimmed = samples.filter { $0.time <= endTime }
        guard let first = trimmed.first, let last = trimmed.last else {
            reset()
            return nil
        }

        let duration = last.time - first.time
        guard duration >= configuration.minimumRideDuration else {
            // Too short to be a ride. Go back to waiting rather than offering
            // the rider a lap they did not take.
            reset()
            return nil
        }

        return RideTrace(samples: trimmed, sampleRateHz: estimatedRate(of: trimmed))
    }

    private func estimatedRate(of samples: [MotionSample]) -> Double {
        guard samples.count > 1 else { return 100 }
        let span = samples[samples.count - 1].time - samples[0].time
        return span > 0 ? Double(samples.count - 1) / span : 100
    }
}
