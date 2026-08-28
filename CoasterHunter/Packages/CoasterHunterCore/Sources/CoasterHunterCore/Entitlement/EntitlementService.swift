import Foundation

/// Resolves what the rider can currently do.
///
/// Apple tracks expiry for auto-renewable subscriptions but not for non-renewing
/// ones, and the 3-Day Park Pass has to be non-renewing because auto-renewable
/// products have a one-week minimum period. So the pass clock is ours to own —
/// which is why it lives here, in tested code, rather than in a view.
public struct EntitlementService: Sendable {

    public init() {}

    /// The rider's effective tier right now.
    public func tier(for entitlements: Entitlements, at date: Date = Date()) -> Tier {
        if entitlements.hasLifetime { return .pro }
        if let expiry = entitlements.subscriptionExpiresAt, date < expiry { return .pro }
        if activePass(in: entitlements, at: date) != nil { return .pass }
        return .free
    }

    public func hasProFeatures(_ entitlements: Entitlements, at date: Date = Date()) -> Bool {
        tier(for: entitlements, at: date).hasProFeatures
    }

    /// The running pass, if one is running. Where several are active — which
    /// should not happen, but might after a restore — the one expiring soonest
    /// wins, so the rider gets the benefit of the later one afterwards.
    public func activePass(in entitlements: Entitlements, at date: Date = Date()) -> ParkPass? {
        entitlements.passes
            .filter { $0.isActive(at: date) }
            .min { lhs, rhs in
                (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
            }
    }

    /// An unused pass waiting to be started.
    public func dormantPass(in entitlements: Entitlements) -> ParkPass? {
        entitlements.passes
            .filter(\.isDormant)
            .min { $0.purchasedAt < $1.purchasedAt }
    }

    /// Start a dormant pass.
    ///
    /// Does nothing when the rider already has Pro or a running pass — starting
    /// a pass they cannot benefit from would burn something they paid for.
    public func activatingPass(
        in entitlements: Entitlements, at date: Date = Date()
    ) -> Entitlements {
        guard tier(for: entitlements, at: date) == .free,
              let dormant = dormantPass(in: entitlements)
        else { return entitlements }

        var updated = entitlements
        if let index = updated.passes.firstIndex(where: { $0.id == dormant.id }) {
            updated.passes[index] = dormant.activated(at: date)
        }
        return updated
    }

    /// Called on park check-in. Starts a dormant pass automatically, because a
    /// rider standing at the gate has unambiguously begun their trip.
    public func onCheckIn(
        _ entitlements: Entitlements, at date: Date = Date()
    ) -> Entitlements {
        activatingPass(in: entitlements, at: date)
    }

    // ------------------------------------------------------------- messaging ---

    /// What to tell the rider about their pass, if anything.
    public func passStatusMessage(
        for entitlements: Entitlements, at date: Date = Date()
    ) -> String? {
        if let active = activePass(in: entitlements, at: date),
           let remaining = active.timeRemaining(at: date) {
            // Round up rather than down. With 47.9 hours left, flooring would
            // say "1 day" when the rider has nearly two — understating time
            // someone has paid for is the worse of the two errors.
            if remaining >= 86_400 {
                let days = Int((remaining / 86_400).rounded(.up))
                return "Park Pass active — \(days) day\(days == 1 ? "" : "s") left"
            }
            if remaining >= 3_600 {
                let hours = Int((remaining / 3_600).rounded(.up))
                return "Park Pass active — \(hours) hour\(hours == 1 ? "" : "s") left"
            }
            let minutes = max(1, Int((remaining / 60).rounded(.up)))
            return "Park Pass ends in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        if dormantPass(in: entitlements) != nil, tier(for: entitlements, at: date) == .free {
            return "Park Pass ready — start it when you arrive"
        }
        return nil
    }

    /// Honest upsell maths for the paywall.
    ///
    /// Four passes cost more than a year, and saying so plainly is worth more
    /// than the handful of extra pass sales that hiding it would win.
    public func passesWorthUpgrading(passPrice: Decimal, annualPrice: Decimal) -> Int? {
        guard passPrice > 0 else { return nil }
        let ratio = (annualPrice as NSDecimalNumber).doubleValue
            / (passPrice as NSDecimalNumber).doubleValue
        let count = Int(ratio.rounded(.up))
        return count > 1 ? count : nil
    }
}

/// Features that are gated. Kept as one list so the paywall and the feature
/// checks can never drift apart.
public enum ProFeature: String, CaseIterable, Sendable {
    case unlimitedSensorTracking
    case rideDNAArchive
    case roughnessAndRowTelemetry
    case pairwiseTopHundred
    case logbookBackdating
    case parkTimeMachine
    case manufacturerStats
    case customStatBuilder
    case offlineParkPacks
    case unlimitedLists
    case fullWrapped
    case widgetsAndComplications

    public var title: String {
        switch self {
        case .unlimitedSensorTracking:  return "Unlimited ride tracking"
        case .rideDNAArchive:           return "Full RideDNA archive"
        case .roughnessAndRowTelemetry: return "Roughness & row-by-row telemetry"
        case .pairwiseTopHundred:       return "Your ranked Top 100"
        case .logbookBackdating:        return "Backdate old trips"
        case .parkTimeMachine:          return "Park history & time machine"
        case .manufacturerStats:        return "Manufacturer & model stats"
        case .customStatBuilder:        return "Custom stat builder"
        case .offlineParkPacks:         return "Offline park packs"
        case .unlimitedLists:           return "Unlimited lists"
        case .fullWrapped:              return "Full Year in Review"
        case .widgetsAndComplications:  return "Widgets & all complications"
        }
    }
}

/// Limits that apply on the free tier.
public enum FreeTierLimits {
    /// Enough to feel it on every visit, not enough for a full park day.
    public static let sensorTrackedLapsPerDay = 3
    public static let customLists = 3
    public static let tripReportHistoryDays = 30
}
