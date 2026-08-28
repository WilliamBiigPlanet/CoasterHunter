import Foundation

/// One "which was better?" answer.
public struct RankingComparison: Codable, Hashable, Sendable {
    public let winnerID: String
    public let loserID: String
    public let decidedAt: Date

    public init(winnerID: String, loserID: String, decidedAt: Date = Date()) {
        self.winnerID = winnerID
        self.loserID = loserID
        self.decidedAt = decidedAt
    }
}

public struct RankedAttraction: Identifiable, Hashable, Sendable {
    public let id: String
    public let rating: Double
    public let comparisons: Int

    /// Ratings settle down as comparisons accumulate; below about five the
    /// position is still noise and the UI should say so rather than imply
    /// a precision it doesn't have.
    public var isSettled: Bool { comparisons >= 5 }
}

/// Builds a personal ranking from pairwise choices instead of star ratings.
///
/// People are bad at absolute scoring — everything drifts to 8/10 — but very
/// good at "this one or that one". Twenty comparisons produce a better-ordered
/// top 100 than a hundred star ratings, and answering them is something you can
/// do while stood in a queue.
public struct EloRanker: Sendable {

    /// Every ride starts here so the numbers stay readable.
    public static let initialRating: Double = 1500

    /// How far one answer can move a rating. Higher settles faster but stays
    /// jumpy; 24 gets a top 10 roughly right inside about 30 comparisons.
    public var kFactor: Double

    /// New rides move faster until they have some history, so a first
    /// comparison isn't drowned out.
    public var provisionalKFactor: Double
    public var provisionalThreshold: Int

    public init(kFactor: Double = 24, provisionalKFactor: Double = 48, provisionalThreshold: Int = 5) {
        self.kFactor = kFactor
        self.provisionalKFactor = provisionalKFactor
        self.provisionalThreshold = provisionalThreshold
    }

    /// Probability that `a` beats `b` given their ratings.
    public static func expectedScore(_ a: Double, _ b: Double) -> Double {
        1 / (1 + pow(10, (b - a) / 400))
    }

    /// Apply every comparison in order and return the standings.
    ///
    /// - Parameter attractionIDs: everything the rider has ridden, so rides that
    ///   have never been compared still appear — unranked, but present.
    public func rank(
        comparisons: [RankingComparison],
        including attractionIDs: [String] = []
    ) -> [RankedAttraction] {
        var ratings: [String: Double] = [:]
        var counts: [String: Int] = [:]

        for id in attractionIDs {
            ratings[id] = Self.initialRating
            counts[id] = 0
        }

        for comparison in comparisons.sorted(by: { $0.decidedAt < $1.decidedAt }) {
            let winner = comparison.winnerID
            let loser = comparison.loserID
            guard winner != loser else { continue }

            let winnerRating = ratings[winner] ?? Self.initialRating
            let loserRating = ratings[loser] ?? Self.initialRating
            let winnerCount = counts[winner] ?? 0
            let loserCount = counts[loser] ?? 0

            let expected = Self.expectedScore(winnerRating, loserRating)
            let winnerK = winnerCount < provisionalThreshold ? provisionalKFactor : kFactor
            let loserK = loserCount < provisionalThreshold ? provisionalKFactor : kFactor

            ratings[winner] = winnerRating + winnerK * (1 - expected)
            ratings[loser] = loserRating - loserK * (1 - expected)
            counts[winner] = winnerCount + 1
            counts[loser] = loserCount + 1
        }

        return ratings
            .map { RankedAttraction(id: $0.key, rating: $0.value, comparisons: counts[$0.key] ?? 0) }
            .sorted {
                $0.rating == $1.rating ? $0.id < $1.id : $0.rating > $1.rating
            }
    }

    /// Choose the next pair to ask about.
    ///
    /// Picks the least-compared ride, then pairs it with whichever ride sits
    /// closest to it in rating — a close contest carries far more information
    /// than a foregone conclusion, so the ranking settles in fewer questions.
    public func nextComparison(
        from standings: [RankedAttraction],
        excluding recentlyAsked: Set<String> = []
    ) -> (String, String)? {
        let pool = standings.filter { !recentlyAsked.contains($0.id) }
        guard pool.count >= 2 else { return nil }

        guard let subject = pool.min(by: {
            $0.comparisons == $1.comparisons
                ? $0.id < $1.id
                : $0.comparisons < $1.comparisons
        }) else { return nil }

        let opponent = pool
            .filter { $0.id != subject.id }
            .min { abs($0.rating - subject.rating) < abs($1.rating - subject.rating) }

        guard let opponent else { return nil }
        return (subject.id, opponent.id)
    }
}
