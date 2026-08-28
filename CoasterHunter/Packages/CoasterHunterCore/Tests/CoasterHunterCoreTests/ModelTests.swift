#if !SHIM_TESTS
import XCTest
@testable import CoasterHunterCore
#endif
import Foundation

final class ModelTests: XCTestCase {

    func testOnlyCoastersCountAsCredits() {
        XCTAssertTrue(AttractionKind.coaster.countsAsCredit)
        for kind in AttractionKind.allCases where kind != .coaster {
            XCTAssertFalse(kind.countsAsCredit, "\(kind) should not count as a credit")
        }
    }

    func testOnlyMeasuredLapsAreEligibleForLeaderboards() {
        // A backdated lap from 2011 has no telemetry and must never compete
        // with one that does.
        XCTAssertTrue(LapSource.sensorConfirmed.eligibleForLeaderboards)
        XCTAssertTrue(LapSource.sensorAutomatic.eligibleForLeaderboards)
        XCTAssertFalse(LapSource.manual.eligibleForLeaderboards)
        XCTAssertFalse(LapSource.backdated.eligibleForLeaderboards)
        XCTAssertFalse(LapSource.imported.eligibleForLeaderboards)
    }

    func testDistanceBetweenKnownPoints() {
        // Cedar Point's entrance to Millennium Force's station.
        let entrance = Coordinate(latitude: 41.4826, longitude: -82.6842)
        let millenniumForce = Coordinate(latitude: 41.48194, longitude: -82.68651)
        let metres = entrance.distance(to: millenniumForce)
        XCTAssertGreaterThan(metres, 100)
        XCTAssertLessThan(metres, 400)

        XCTAssertEqual(entrance.distance(to: entrance), 0, accuracy: 0.001)
    }

    func testRowCountNeedsTheWholeTrainLayout() {
        var spec = AttractionSpec(attractionID: "x")
        XCTAssertNil(spec.rowCount)
        spec.carsPerTrain = 9
        XCTAssertNil(spec.rowCount)
        spec.rowsPerCar = 2
        XCTAssertEqual(spec.rowCount, 18)
    }

    func testParkVisitStaysOpenUntilCheckOut() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var visit = ParkVisit(parkID: "cedar-point", checkedInAt: start)
        XCTAssertTrue(visit.isOpen)
        XCTAssertEqual(visit.duration(now: start.addingTimeInterval(3600)), 3600, accuracy: 0.1)

        visit.checkedOutAt = start.addingTimeInterval(7200)
        XCTAssertFalse(visit.isOpen)
        XCTAssertEqual(visit.duration(now: start.addingTimeInterval(99999)), 7200, accuracy: 0.1)
    }

    func testLapWithoutSensorDataIsStillValid() {
        let lap = Lap(attractionID: "a", riddenAt: Date())
        XCTAssertFalse(lap.hasSensorData)
        XCTAssertEqual(lap.source, .manual)
    }

    func testModelsRoundTripThroughJSON() throws {
        let lap = Lap(
            attractionID: "millennium-force", riddenAt: Date(timeIntervalSince1970: 1_800_000_000),
            row: 9,
            metrics: MetricsCalculator.metrics(for: TraceFixtures.airtimeMachine()),
            source: .sensorConfirmed)

        let data = try JSONEncoder().encode(lap)
        let decoded = try JSONDecoder().decode(Lap.self, from: data)

        XCTAssertEqual(decoded.attractionID, lap.attractionID)
        XCTAssertEqual(decoded.row, 9)
        XCTAssertEqual(decoded.metrics?.airtimeMoments, lap.metrics?.airtimeMoments)
    }
}
