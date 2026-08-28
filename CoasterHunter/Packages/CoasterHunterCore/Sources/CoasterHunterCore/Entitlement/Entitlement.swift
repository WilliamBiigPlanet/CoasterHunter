import Foundation

/// What the rider has paid for.
public enum Tier: String, Codable, Sendable, Comparable {
    case free
    case pass    // 3-Day Park Pass — full Pro features, fixed duration
    case pro     // annual subscription or lifetime

    private var order: Int {
        switch self {
        case .free: return 0
        case .pass: return 1
        case .pro:  return 2
        }
    }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.order < rhs.order }

    /// The pass unlocks everything Pro does. It differs in duration, not scope —
    /// a paywall that sold a cheaper tier with features quietly missing would be
    /// the kind of thing an enthusiast community screenshots.
    public var hasProFeatures: Bool { self != .free }
}

/// StoreKit product identifiers.
public enum ProductID {
    public static let threeDayPass = "com.coasterhunter.pass.3day"
    public static let annual = "com.coasterhunter.pro.annual"
    public static let lifetime = "com.coasterhunter.pro.lifetime"

    public static let all = [threeDayPass, annual, lifetime]
}

/// A purchased 3-Day Park Pass.
///
/// Bought and activated separately on purpose. People buy the pass the night
/// before a trip — on the train, in the hotel — and if the clock started at
/// purchase they would lose a day of what they paid for. So a purchase creates a
/// dormant pass, and it starts when the rider says so or when they first check
/// into a park.
public struct ParkPass: Identifiable, Codable, Hashable, Sendable {
    public static let duration: TimeInterval = 3 * 24 * 60 * 60

    public let id: UUID
    public let purchasedAt: Date
    public var activatedAt: Date?

    public init(id: UUID = UUID(), purchasedAt: Date, activatedAt: Date? = nil) {
        self.id = id
        self.purchasedAt = purchasedAt
        self.activatedAt = activatedAt
    }

    public var expiresAt: Date? {
        activatedAt.map { $0.addingTimeInterval(Self.duration) }
    }

    public var isDormant: Bool { activatedAt == nil }

    public func isActive(at date: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return date < expiresAt
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return date >= expiresAt
    }

    public func timeRemaining(at date: Date = Date()) -> TimeInterval? {
        guard let expiresAt, date < expiresAt else { return nil }
        return expiresAt.timeIntervalSince(date)
    }

    public func activated(at date: Date = Date()) -> ParkPass {
        guard isDormant else { return self }
        return ParkPass(id: id, purchasedAt: purchasedAt, activatedAt: date)
    }
}

/// Everything the rider owns. Resolved into a single effective `Tier`.
public struct Entitlements: Codable, Hashable, Sendable {
    public var hasLifetime: Bool
    /// Expiry of the annual subscription, from StoreKit. Nil when not subscribed.
    public var subscriptionExpiresAt: Date?
    /// Passes are consumable-ish: several can be owned, used one at a time.
    public var passes: [ParkPass]

    public init(
        hasLifetime: Bool = false,
        subscriptionExpiresAt: Date? = nil,
        passes: [ParkPass] = []
    ) {
        self.hasLifetime = hasLifetime
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.passes = passes
    }
}
