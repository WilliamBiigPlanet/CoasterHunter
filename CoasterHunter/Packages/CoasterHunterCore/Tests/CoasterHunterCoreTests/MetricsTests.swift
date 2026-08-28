#if !SHIM_TESTS
import XCTest
@testable import CoasterHunterCore
#endif
import Foundation

final class MetricsTests: XCTestCase {

    // ------------------------------------------------------------- airtime ---

    func testFlatTraceHasNoAirtime() throws {
        let metrics = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.flat()))
        XCTAssertEqual(metrics.airtimeSeconds, 0)
        XCTAssertEqual(metrics.sustainedAirtimeSeconds, 0)
        XCTAssertEqual(metrics.airtimeMoments, 0)
        XCTAssertEqual(metrics.inversions, 0)
    }

    func testAirtimeMatchesTheConstructedWindows() throws {
        // 1.2 + 1.0 + 0.6 = 2.8 s, all three long enough to be sustained.
        let metrics = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.airtimeMachine()))
        XCTAssertEqual(metrics.airtimeSeconds, 2.8, accuracy: 0.05)
        XCTAssertEqual(metrics.sustainedAirtimeSeconds, 2.8, accuracy: 0.05)
        XCTAssertEqual(metrics.airtimeMoments, 3)
    }

    func testShortBumpIsNotCountedAsSustainedAirtime() throws {
        // 0.15 s below threshold: real, but under the 0.4 s a rider would feel.
        let metrics = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.shortBump()))
        XCTAssertGreaterThan(metrics.airtimeSeconds, 0)
        XCTAssertEqual(metrics.sustainedAirtimeSeconds, 0)
        XCTAssertEqual(metrics.airtimeMoments, 0)
    }

    // ---------------------------------------------------------- g measures ---

    func testPeakGIgnoresIsolatedSpikes() throws {
        // One 9 g sample in an otherwise 1 g trace is an arm hitting a restraint,
        // not the ride. The 99th percentile should shrug it off.
        var samples = TraceFixtures.flat(duration: 10).samples
        samples[500] = MotionSample(time: samples[500].time, verticalG: 9.0)
        let metrics = try XCTUnwrap(
            MetricsCalculator.metrics(for: RideTrace(samples: samples)))
        XCTAssertLessThan(metrics.peakVerticalG, 2.0)
    }

    func testEjectorAirtimeShowsAsNegativeMinimum() throws {
        let metrics = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.airtimeMachine()))
        XCTAssertLessThan(metrics.minVerticalG, 0)
        XCTAssertGreaterThan(metrics.peakVerticalG, 1.0)
    }

    // ---------------------------------------------------------- inversions ---

    func testInversionsAreCounted() throws {
        let metrics = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.looper()))
        XCTAssertEqual(metrics.inversions, 4)
    }

    func testUprightRideReportsNoInversions() throws {
        let metrics = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.airtimeMachine()))
        XCTAssertEqual(metrics.inversions, 0)
    }

    func testBriefTiltIsNotAnInversion() {
        // A 0.1 s flick past the tilt threshold — a banked turn, not a loop.
        var samples: [MotionSample] = []
        for i in 0..<1000 {
            let t = Double(i) / 100
            let inverted = t >= 5.0 && t < 5.1
            samples.append(MotionSample(
                time: t, verticalG: 1.0, gravityY: inverted ? -1 : 1))
        }
        let count = MetricsCalculator.countInversions(
            samples, thresholds: MetricsCalculator.Thresholds())
        XCTAssertEqual(count, 0)
    }

    // ----------------------------------------------------------- roughness ---

    func testRoughRideScoresHigherThanSmoothRide() throws {
        let smooth = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.smooth()))
        let rough = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.rough()))
        XCTAssertGreaterThan(rough.roughnessIndex, smooth.roughnessIndex)
        XCTAssertLessThan(smooth.roughnessIndex, 1.0, "a smooth ride should read near zero")
    }

    func testRoughnessRisesWithRattleAmplitude() throws {
        let mild = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.rough(amplitude: 0.3)))
        let harsh = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.rough(amplitude: 1.5)))
        XCTAssertGreaterThan(harsh.roughnessIndex, mild.roughnessIndex)
    }

    func testRoughnessStaysInRange() throws {
        let extreme = try XCTUnwrap(MetricsCalculator.metrics(for: TraceFixtures.rough(amplitude: 40)))
        XCTAssertLessThanOrEqual(extreme.roughnessIndex, 10)
        XCTAssertGreaterThanOrEqual(extreme.roughnessIndex, 0)
    }

    // ---------------------------------------------------------- ride score ---

    func testRideScoreStaysWithinBounds() {
        let low = MetricsCalculator.rideScore(
            peakVerticalG: 1, minVerticalG: 1, peakLateralG: 0,
            sustainedAirtime: 0, inversions: 0, duration: 0)
        let high = MetricsCalculator.rideScore(
            peakVerticalG: 6, minVerticalG: -2, peakLateralG: 4,
            sustainedAirtime: 20, inversions: 14, duration: 300)
        XCTAssertEqual(low, 0)
        XCTAssertEqual(high, 100)
    }

    func testAirtimeMovesTheScoreMoreThanPositiveG() {
        // Airtime is what enthusiasts chase; the score has to reflect that or it
        // just ranks rides by how hard they pull through the bottom of a drop.
        let airtimeHeavy = MetricsCalculator.rideScore(
            peakVerticalG: 2, minVerticalG: -0.5, peakLateralG: 0,
            sustainedAirtime: 8, inversions: 0, duration: 100)
        let gHeavy = MetricsCalculator.rideScore(
            peakVerticalG: 5, minVerticalG: 0.9, peakLateralG: 0,
            sustainedAirtime: 0, inversions: 0, duration: 100)
        XCTAssertGreaterThan(airtimeHeavy, gHeavy)
    }

    // ------------------------------------------------------------ plumbing ---

    func testEmptyTraceProducesNoMetrics() {
        XCTAssertNil(MetricsCalculator.metrics(for: RideTrace(samples: [])))
        XCTAssertNil(MetricsCalculator.metrics(
            for: RideTrace(samples: [MotionSample(time: 0, verticalG: 1)])))
    }

    func testPercentileInterpolates() {
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]
        XCTAssertEqual(MetricsCalculator.percentile(values, 0), 1.0)
        XCTAssertEqual(MetricsCalculator.percentile(values, 1), 5.0)
        XCTAssertEqual(MetricsCalculator.percentile(values, 0.5), 3.0)
        XCTAssertEqual(MetricsCalculator.percentile([], 0.5), 0)
    }

    func testTiltDegreesReadsTheGravityVector() {
        XCTAssertEqual(MotionSample(time: 0, verticalG: 1, gravityY: 1).tiltDegrees, 0, accuracy: 0.1)
        XCTAssertEqual(MotionSample(time: 0, verticalG: 1, gravityY: -1).tiltDegrees, 180, accuracy: 0.1)
        XCTAssertEqual(
            MotionSample(time: 0, verticalG: 1, gravityX: 1, gravityY: 0).tiltDegrees,
            90, accuracy: 0.1)
    }

    func testDownsamplingKeepsThePeaks() {
        let trace = TraceFixtures.airtimeMachine()
        let small = trace.downsampled(to: 128)
        XCTAssertLessThanOrEqual(small.samples.count, 128)

        // The ejector moments must survive, or the RideDNA graphic lies.
        let minimum = small.samples.map(\.verticalG).min() ?? 1
        XCTAssertLessThan(minimum, 0, "downsampling flattened the airtime")
    }
}

final class CaptureSessionTests: XCTestCase {

    /// Drive a session with a fixture, plus quiet padding either side.
    private func run(_ trace: RideTrace, padding: Double = 8) -> RideTrace? {
        let session = RideCaptureSession()
        var result: RideTrace?
        var clock = 0.0
        let step = 1.0 / 100

        while clock < padding {
            _ = session.ingest(MotionSample(time: clock, verticalG: 1.0))
            clock += step
        }
        for sample in trace.samples {
            let shifted = MotionSample(
                time: clock + sample.time, verticalG: sample.verticalG,
                lateralG: sample.lateralG, longitudinalG: sample.longitudinalG,
                gravityX: sample.gravityX, gravityY: sample.gravityY, gravityZ: sample.gravityZ)
            if let finished = session.ingest(shifted) { result = finished }
        }
        let after = clock + trace.duration
        clock = after
        while clock < after + padding, result == nil {
            result = session.ingest(MotionSample(time: clock, verticalG: 1.0))
            clock += step
        }
        return result
    }

    func testStartsIdle() {
        XCTAssertEqual(RideCaptureSession().state, .idle)
    }

    func testWalkingDoesNotStartACapture() {
        let session = RideCaptureSession()
        var clock = 0.0
        // A brisk walk: rhythmic, but never far from 1 g for long.
        while clock < 30 {
            let g = 1.0 + 0.3 * sin(clock * 2 * .pi * 1.8)
            _ = session.ingest(MotionSample(time: clock, verticalG: g))
            clock += 0.01
        }
        XCTAssertEqual(session.state, .idle)
    }

    func testCapturesARideAndReturnsATrace() throws {
        let trace = try XCTUnwrap(run(TraceFixtures.looper()))
        XCTAssertGreaterThan(trace.duration, 20)
        XCTAssertGreaterThan(trace.samples.count, 1000)
    }

    func testALongMidCourseBrakeRunStillCountsAsOneLap() {
        // Several layouts hold on the mid-course for five seconds. Splitting
        // there would double the rider's lap count on those rides.
        let session = RideCaptureSession()
        var clock = 0.0
        var finishes = 0
        func feed(_ g: Double, seconds: Double) {
            let end = clock + seconds
            while clock < end {
                if session.ingest(MotionSample(time: clock, verticalG: g)) != nil { finishes += 1 }
                clock += 0.01
            }
        }
        feed(1.0, seconds: 3)
        feed(3.0, seconds: 25)
        feed(1.0, seconds: 5.5)   // long mid-course brake
        feed(3.0, seconds: 15)
        feed(1.0, seconds: 12)    // station

        XCTAssertEqual(finishes, 1)
    }

    func testShortBurstIsNotOfferedAsALap() {
        // Three seconds of violent movement is an arm swing, not a coaster.
        let session = RideCaptureSession()
        var clock = 0.0
        var result: RideTrace?
        while clock < 3 {
            result = session.ingest(MotionSample(time: clock, verticalG: 3.0)) ?? result
            clock += 0.01
        }
        while clock < 12 {
            result = session.ingest(MotionSample(time: clock, verticalG: 1.0)) ?? result
            clock += 0.01
        }
        XCTAssertNil(result)
    }

    func testMidCourseBrakeRunDoesNotSplitTheLap() {
        // Two active sections separated by 2 s of coasting. That is one lap.
        let session = RideCaptureSession()
        var clock = 0.0
        var finishes = 0
        func feed(_ g: Double, seconds: Double) {
            let end = clock + seconds
            while clock < end {
                if session.ingest(MotionSample(time: clock, verticalG: g)) != nil { finishes += 1 }
                clock += 0.01
            }
        }
        feed(1.0, seconds: 3)
        feed(3.0, seconds: 20)
        feed(1.0, seconds: 2.0)   // brake run — shorter than restDuration
        feed(3.0, seconds: 20)
        feed(1.0, seconds: 8)     // station

        XCTAssertEqual(finishes, 1, "the brake run should not have ended the lap")
    }

    func testResetReturnsToIdle() {
        let session = RideCaptureSession()
        var clock = 0.0
        while clock < 5 {
            _ = session.ingest(MotionSample(time: clock, verticalG: 3.0))
            clock += 0.01
        }
        XCTAssertEqual(session.state, .capturing)
        session.reset()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.samples.isEmpty)
    }
}
