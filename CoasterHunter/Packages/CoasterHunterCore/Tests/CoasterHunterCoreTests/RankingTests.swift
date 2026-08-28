#if !SHIM_TESTS
import XCTest
@testable import CoasterHunterCore
#endif
import Foundation

final class RankingTests: XCTestCase {

    private func comparisons(_ pairs: [(String, String)]) -> [RankingComparison] {
        pairs.enumerated().map { index, pair in
            RankingComparison(
                winnerID: pair.0, loserID: pair.1,
                decidedAt: Date(timeIntervalSince1970: Double(index)))
        }
    }

    func testConsistentWinnerRisesToTheTop() {
        let ranker = EloRanker()
        let standings = ranker.rank(
            comparisons: comparisons([
                ("nemesis", "oblivion"), ("nemesis", "smiler"), ("nemesis", "rita"),
                ("oblivion", "rita"), ("smiler", "rita"), ("nemesis", "oblivion"),
            ]),
            including: ["nemesis", "oblivion", "smiler", "rita"])

        XCTAssertEqual(standings.first?.id, "nemesis")
        XCTAssertEqual(standings.last?.id, "rita")
    }

    func testRatingsConvergeToATrueOrdering() {
        // Feed a known preference order and check it is recovered. Every pair is
        // compared repeatedly so the ratings have a chance to settle.
        let truth = ["a", "b", "c", "d", "e"]
        var pairs: [(String, String)] = []
        for _ in 0..<12 {
            for i in 0..<truth.count {
                for j in (i + 1)..<truth.count {
                    pairs.append((truth[i], truth[j]))
                }
            }
        }
        let standings = EloRanker().rank(comparisons: comparisons(pairs), including: truth)
        XCTAssertEqual(standings.map(\.id), truth)
    }

    func testRidesWithNoComparisonsStillAppear() {
        let standings = EloRanker().rank(
            comparisons: comparisons([("a", "b")]),
            including: ["a", "b", "never-compared"])

        let unranked = standings.first { $0.id == "never-compared" }
        XCTAssertNotNil(unranked)
        XCTAssertEqual(unranked?.comparisons, 0)
        XCTAssertFalse(unranked?.isSettled ?? true)
        XCTAssertEqual(unranked?.rating, EloRanker.initialRating)
    }

    func testExpectedScoreIsSymmetric() {
        XCTAssertEqual(EloRanker.expectedScore(1500, 1500), 0.5, accuracy: 0.0001)
        let a = EloRanker.expectedScore(1600, 1400)
        let b = EloRanker.expectedScore(1400, 1600)
        XCTAssertEqual(a + b, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(a, 0.7)
    }

    func testSelfComparisonIsIgnored() {
        let standings = EloRanker().rank(
            comparisons: comparisons([("a", "a")]), including: ["a", "b"])
        XCTAssertEqual(standings.first { $0.id == "a" }?.comparisons, 0)
    }

    func testNextComparisonPicksTheLeastKnownRide() {
        let standings = [
            RankedAttraction(id: "well-known", rating: 1600, comparisons: 20),
            RankedAttraction(id: "unknown", rating: 1500, comparisons: 0),
            RankedAttraction(id: "middling", rating: 1520, comparisons: 8),
        ]
        let pair = EloRanker().nextComparison(from: standings)
        XCTAssertEqual(pair?.0, "unknown")
        // Paired with its nearest rival — a close contest is more informative
        // than one whose answer is obvious.
        XCTAssertEqual(pair?.1, "middling")
    }

    func testNextComparisonNeedsTwoCandidates() {
        XCTAssertNil(EloRanker().nextComparison(
            from: [RankedAttraction(id: "only", rating: 1500, comparisons: 0)]))
    }
}
