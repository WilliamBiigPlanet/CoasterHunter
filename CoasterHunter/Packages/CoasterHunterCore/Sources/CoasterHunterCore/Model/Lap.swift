import Foundation

/// One ride on one attraction. The atomic unit of the whole app.
///
/// A lap can exist without any sensor data — logged by tapping the watch, or
/// backdated from memory — so `metrics` is optional and the UI must never
/// assume it is present.
public struct Lap: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let attractionID: String
    public let parkVisitID: UUID?
    public let riddenAt: Date

    /// Row on the train, 1-indexed from the front. Nil when not recorded.
    public var row: Int?
    public var trainName: String?
    public var seatNumber: Int?
    public var note: String?

    /// Derived sensor measurements, when the watch was capturing.
    public var metrics: LapMetrics?

    /// How the lap came to be recorded — matters for leaderboard integrity.
    public var source: LapSource

    public init(
        id: UUID = UUID(), attractionID: String, parkVisitID: UUID? = nil,
        riddenAt: Date, row: Int? = nil, trainName: String? = nil,
        seatNumber: Int? = nil, note: String? = nil,
        metrics: LapMetrics? = nil, source: LapSource = .manual
    ) {
        self.id = id
        self.attractionID = attractionID
        self.parkVisitID = parkVisitID
        self.riddenAt = riddenAt
        self.row = row
        self.trainName = trainName
        self.seatNumber = seatNumber
        self.note = note
        self.metrics = metrics
        self.source = source
    }

    public var hasSensorData: Bool { metrics != nil }
}

public enum LapSource: String, Codable, Sendable {
    /// Tapped by the rider, on phone or watch.
    case manual
    /// Captured by the watch and confirmed by the rider.
    case sensorConfirmed
    /// Captured and matched automatically above the confidence threshold.
    case sensorAutomatic
    /// Entered after the fact through the logbook.
    case backdated
    /// Brought across from another app.
    case imported

    /// Only measured laps may set records. A backdated lap from 2011 has no
    /// telemetry and must never compete with one that does.
    public var eligibleForLeaderboards: Bool {
        self == .sensorConfirmed || self == .sensorAutomatic
    }
}

/// A day at a park. Check in on arrival; laps attach to it automatically.
public struct ParkVisit: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let parkID: String
    public var checkedInAt: Date
    public var checkedOutAt: Date?
    public var steps: Int?
    public var distanceMetres: Double?

    public init(
        id: UUID = UUID(), parkID: String, checkedInAt: Date,
        checkedOutAt: Date? = nil, steps: Int? = nil, distanceMetres: Double? = nil
    ) {
        self.id = id
        self.parkID = parkID
        self.checkedInAt = checkedInAt
        self.checkedOutAt = checkedOutAt
        self.steps = steps
        self.distanceMetres = distanceMetres
    }

    public var isOpen: Bool { checkedOutAt == nil }

    public func duration(now: Date = Date()) -> TimeInterval {
        (checkedOutAt ?? now).timeIntervalSince(checkedInAt)
    }
}
