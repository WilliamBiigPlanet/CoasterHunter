import Foundation

/// What sort of thing you are queueing for.
///
/// `other` is a real answer, not a failure — parks list game booths, gardens and
/// character meets alongside rides, and guessing at those would be worse than
/// admitting we don't know.
public enum AttractionKind: String, Codable, CaseIterable, Sendable {
    case coaster, dark, water, flat, show, transport, other

    public var displayName: String {
        switch self {
        case .coaster:   return "Roller coaster"
        case .dark:      return "Dark ride"
        case .water:     return "Water ride"
        case .flat:      return "Flat ride"
        case .show:      return "Show"
        case .transport: return "Transport"
        case .other:     return "Other"
        }
    }

    /// Kinds that count towards a credit total. Enthusiasts count coasters.
    public var countsAsCredit: Bool { self == .coaster }
}

public enum OperatingStatus: String, Codable, Sendable {
    case operating, defunct, planned, relocated, closedTemporarily
}

public struct Park: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let destinationID: String?
    public let name: String
    public let country: String?
    public let latitude: Double?
    public let longitude: Double?
    public let timeZoneIdentifier: String?
    public let openedYear: Int?

    public init(
        id: String, destinationID: String? = nil, name: String,
        country: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
        timeZoneIdentifier: String? = nil, openedYear: Int? = nil
    ) {
        self.id = id
        self.destinationID = destinationID
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.openedYear = openedYear
    }

    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

public struct Attraction: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let parkID: String
    public let name: String
    public let kind: AttractionKind
    public let status: OperatingStatus
    public let areaName: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        id: String, parkID: String, name: String, kind: AttractionKind,
        status: OperatingStatus = .operating, areaName: String? = nil,
        latitude: Double? = nil, longitude: Double? = nil
    ) {
        self.id = id
        self.parkID = parkID
        self.name = name
        self.kind = kind
        self.status = status
        self.areaName = areaName
        self.latitude = latitude
        self.longitude = longitude
    }

    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// Everything measured about a ride, as published. All metric.
///
/// Almost every field is optional because the free sources are incomplete — a
/// missing height is a gap a user submission can fill, and the UI has to show
/// gaps honestly rather than printing a zero.
public struct AttractionSpec: Codable, Hashable, Sendable {
    public let attractionID: String
    public var manufacturer: String?
    public var model: String?
    public var designer: String?
    public var openedYear: Int?
    public var closedYear: Int?
    public var heightMetres: Double?
    public var dropMetres: Double?
    public var lengthMetres: Double?
    public var speedKmh: Double?
    public var inversions: Int?
    public var durationSeconds: Int?
    public var maxAngleDegrees: Double?
    public var maxGForce: Double?
    public var heightRestrictionCm: Int?
    public var trains: Int?
    public var carsPerTrain: Int?
    public var rowsPerCar: Int?
    public var ridersPerRow: Int?

    public init(attractionID: String) {
        self.attractionID = attractionID
    }

    /// Rows a rider can choose, when the layout is known. Drives the
    /// row-by-row telemetry comparison.
    public var rowCount: Int? {
        guard let carsPerTrain, let rowsPerCar else { return nil }
        return carsPerTrain * rowsPerCar
    }
}
