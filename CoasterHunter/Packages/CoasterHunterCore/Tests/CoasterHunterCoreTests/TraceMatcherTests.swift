#if !SHIM_TESTS
import XCTest
@testable import CoasterHunterCore
#endif
import Foundation

final class TraceMatcherTests: XCTestCase {

    private func template(from trace: RideTrace, id: String, laps: Int = 10) -> RideTemplate {
        RideTemplate(
            attractionID: id,
            profile: TraceMatcher.profile(from: trace),
            lapCount: laps,
            meanDuration: trace.duration)
    }

    func testProfileIsFixedLengthAndNormalised() {
        let profile = TraceMatcher.profile(from: TraceFixtures.airtimeMachine())
        XCTAssertEqual(profile.count, TraceMatcher.profileLength)

        let mean = profile.reduce(0, +) / Double(profile.count)
        XCTAssertEqual(mean, 0, accuracy: 0.001, "profile should be zero-mean")
    }

    func testIdenticalTracesWarpToZeroDistance() {
        let profile = TraceMatcher.profile(from: TraceFixtures.airtimeMachine())
        XCTAssertEqual(TraceMatcher.warpDistance(profile, profile), 0, accuracy: 0.0001)
    }

    func testDifferentRidesAreFurtherApartThanTheSameRide() {
        let airtime = TraceMatcher.profile(from: TraceFixtures.airtimeMachine())
        let looper = TraceMatcher.profile(from: TraceFixtures.looper())
        let sameRideAgain = TraceMatcher.profile(
            from: TraceFixtures.timeStretched(TraceFixtures.airtimeMachine(), by: 1.06))

        XCTAssertLessThan(
            TraceMatcher.warpDistance(airtime, sameRideAgain),
            TraceMatcher.warpDistance(airtime, looper))
    }

    func testMatchesTheRightRideAmongCandidates() throws {
        let candidates = [
            template(from: TraceFixtures.airtimeMachine(), id: "airtime"),
            template(from: TraceFixtures.looper(), id: "looper"),
            template(from: TraceFixtures.smooth(), id: "smooth"),
        ]
        let match = try XCTUnwrap(
            TraceMatcher.match(trace: TraceFixtures.looper(), candidates: candidates))
        XCTAssertEqual(match.attractionID, "looper")
        XCTAssertGreaterThan(match.confidence, TraceMatcher.autoLogThreshold)
    }

    func testToleratesASlowerTrain() throws {
        // A full train on a cold morning runs several per cent slower. Warping
        // the time axis is the entire reason this uses DTW rather than a
        // point-by-point comparison.
        let candidates = [
            template(from: TraceFixtures.looper(), id: "looper"),
            template(from: TraceFixtures.airtimeMachine(), id: "airtime"),
        ]
        let slower = TraceFixtures.timeStretched(TraceFixtures.looper(), by: 1.08)
        let match = try XCTUnwrap(TraceMatcher.match(trace: slower, candidates: candidates))
        XCTAssertEqual(match.attractionID, "looper")
    }

    func testRejectsATraceOfObviouslyWrongLength() {
        // Same shape, but taking twice as long. That is a different ride.
        let candidates = [template(from: TraceFixtures.looper(), id: "looper")]
        let doubled = TraceFixtures.timeStretched(TraceFixtures.looper(), by: 2.0)
        XCTAssertNil(TraceMatcher.match(trace: doubled, candidates: candidates))
    }

    func testYoungTemplatesReportLowerConfidence() throws {
        let mature = [template(from: TraceFixtures.looper(), id: "looper", laps: 20)]
        let young = [template(from: TraceFixtures.looper(), id: "looper", laps: 1)]

        let matureMatch = try XCTUnwrap(
            TraceMatcher.match(trace: TraceFixtures.looper(), candidates: mature))
        let youngMatch = try XCTUnwrap(
            TraceMatcher.match(trace: TraceFixtures.looper(), candidates: young))

        XCTAssertGreaterThan(matureMatch.confidence, youngMatch.confidence)
        XCTAssertLessThan(
            youngMatch.confidence, TraceMatcher.autoLogThreshold,
            "a template built from one lap must not auto-log")
    }

    func testNoCandidatesMeansNoMatch() {
        XCTAssertNil(TraceMatcher.match(trace: TraceFixtures.looper(), candidates: []))
        XCTAssertNil(TraceMatcher.match(trace: RideTrace(samples: []), candidates: []))
    }

    func testTemplateBuildsUpAcrossConfirmedLaps() {
        var template: RideTemplate?
        for _ in 0..<5 {
            template = TraceMatcher.updated(
                template: template, with: TraceFixtures.looper(), attractionID: "looper")
        }
        let built = try? XCTUnwrap(template)
        XCTAssertEqual(built?.lapCount, 5)
        XCTAssertEqual(built?.profile.count, TraceMatcher.profileLength)
        XCTAssertEqual(built?.meanDuration ?? 0, TraceFixtures.looper().duration, accuracy: 0.1)
    }
}
