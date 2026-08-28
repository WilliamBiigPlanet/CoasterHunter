#if !SHIM_TESTS
import XCTest
@testable import CoasterHunterCore
#endif
import Foundation

final class EntitlementTests: XCTestCase {

    private let service = EntitlementService()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func hours(_ n: Double) -> TimeInterval { n * 3600 }

    // ---------------------------------------------------------------- tiers ---

    func testNoPurchasesMeansFree() {
        XCTAssertEqual(service.tier(for: Entitlements(), at: now), .free)
        XCTAssertFalse(service.hasProFeatures(Entitlements(), at: now))
    }

    func testLifetimeIsAlwaysPro() {
        let owned = Entitlements(hasLifetime: true)
        XCTAssertEqual(service.tier(for: owned, at: now), .pro)
        XCTAssertEqual(service.tier(for: owned, at: now.addingTimeInterval(hours(24 * 3650))), .pro)
    }

    func testSubscriptionLapsesAtItsExpiry() {
        let subscribed = Entitlements(subscriptionExpiresAt: now.addingTimeInterval(hours(1)))
        XCTAssertEqual(service.tier(for: subscribed, at: now), .pro)
        XCTAssertEqual(service.tier(for: subscribed, at: now.addingTimeInterval(hours(2))), .free)
    }

    // ----------------------------------------------------------- park pass ---

    func testPurchasedPassGrantsNothingUntilItIsStarted() {
        // The whole point: buying the night before must not burn a day.
        let bought = Entitlements(passes: [ParkPass(purchasedAt: now)])
        XCTAssertEqual(service.tier(for: bought, at: now), .free)
        XCTAssertNotNil(service.dormantPass(in: bought))
        XCTAssertNil(service.activePass(in: bought, at: now))
    }

    func testActivatedPassGrantsProFeaturesForThreeDays() {
        var owned = Entitlements(passes: [ParkPass(purchasedAt: now)])
        owned = service.activatingPass(in: owned, at: now)

        XCTAssertEqual(service.tier(for: owned, at: now), .pass)
        XCTAssertTrue(service.hasProFeatures(owned, at: now))

        // Still running just before the three days are up.
        let justBefore = now.addingTimeInterval(hours(71.9))
        XCTAssertEqual(service.tier(for: owned, at: justBefore), .pass)

        // Gone just after.
        let justAfter = now.addingTimeInterval(hours(72.1))
        XCTAssertEqual(service.tier(for: owned, at: justAfter), .free)
    }

    func testPassUnlocksEverythingProDoes() {
        // Scope is identical; only the duration differs.
        XCTAssertTrue(Tier.pass.hasProFeatures)
        XCTAssertTrue(Tier.pro.hasProFeatures)
        XCTAssertFalse(Tier.free.hasProFeatures)
    }

    func testCheckingInStartsADormantPass() {
        let bought = Entitlements(passes: [ParkPass(purchasedAt: now.addingTimeInterval(-hours(12)))])
        let afterCheckIn = service.onCheckIn(bought, at: now)

        XCTAssertEqual(service.tier(for: afterCheckIn, at: now), .pass)
        XCTAssertEqual(service.activePass(in: afterCheckIn, at: now)?.expiresAt,
                       now.addingTimeInterval(ParkPass.duration))
    }

    func testCheckingInDoesNotBurnAPassWhenAlreadySubscribed() {
        // A Pro subscriber who also owns a pass must keep the pass for later.
        let both = Entitlements(
            subscriptionExpiresAt: now.addingTimeInterval(hours(24 * 300)),
            passes: [ParkPass(purchasedAt: now)])

        let afterCheckIn = service.onCheckIn(both, at: now)
        XCTAssertTrue(service.dormantPass(in: afterCheckIn) != nil, "the pass should be untouched")
        XCTAssertEqual(service.tier(for: afterCheckIn, at: now), .pro)
    }

    func testCheckingInTwiceDoesNotStartASecondPass() {
        let bought = Entitlements(passes: [
            ParkPass(purchasedAt: now), ParkPass(purchasedAt: now),
        ])
        var owned = service.onCheckIn(bought, at: now)
        owned = service.onCheckIn(owned, at: now.addingTimeInterval(hours(2)))

        XCTAssertEqual(owned.passes.filter { !$0.isDormant }.count, 1)
        XCTAssertEqual(owned.passes.filter(\.isDormant).count, 1)
    }

    func testASecondPassStartsOnlyOnceTheFirstHasExpired() {
        let bought = Entitlements(passes: [
            ParkPass(purchasedAt: now), ParkPass(purchasedAt: now),
        ])
        var owned = service.onCheckIn(bought, at: now)

        let afterExpiry = now.addingTimeInterval(hours(80))
        XCTAssertEqual(service.tier(for: owned, at: afterExpiry), .free)

        owned = service.onCheckIn(owned, at: afterExpiry)
        XCTAssertEqual(service.tier(for: owned, at: afterExpiry), .pass)
    }

    func testExpiredPassStaysExpired() {
        let started = ParkPass(purchasedAt: now, activatedAt: now)
        let owned = Entitlements(passes: [started])
        let later = now.addingTimeInterval(hours(100))

        XCTAssertTrue(started.isExpired(at: later))
        XCTAssertNil(started.timeRemaining(at: later))
        XCTAssertEqual(service.tier(for: owned, at: later), .free)
        XCTAssertNil(service.dormantPass(in: owned), "an expired pass is not reusable")
    }

    // ---------------------------------------------------------- messaging ---

    func testPassStatusMessageCountsDown() {
        var owned = Entitlements(passes: [ParkPass(purchasedAt: now)])

        XCTAssertEqual(service.passStatusMessage(for: owned, at: now),
                       "Park Pass ready — start it when you arrive")

        owned = service.activatingPass(in: owned, at: now)
        XCTAssertEqual(service.passStatusMessage(for: owned, at: now),
                       "Park Pass active — 3 days left")

        // The boundary that matters: with 47.9 hours left the rider still has
        // nearly two days, and must not be told they have one.
        XCTAssertEqual(service.passStatusMessage(for: owned, at: now.addingTimeInterval(hours(24.1))),
                       "Park Pass active — 2 days left")
        XCTAssertEqual(service.passStatusMessage(for: owned, at: now.addingTimeInterval(hours(48))),
                       "Park Pass active — 1 day left")
        XCTAssertEqual(service.passStatusMessage(for: owned, at: now.addingTimeInterval(hours(69))),
                       "Park Pass active — 3 hours left")
        XCTAssertEqual(service.passStatusMessage(for: owned, at: now.addingTimeInterval(hours(71.9))),
                       "Park Pass ends in 6 minutes")
        XCTAssertNil(service.passStatusMessage(for: owned, at: now.addingTimeInterval(hours(80))))
    }

    func testUpsellMathsIsStatedHonestly() {
        // £4.99 pass, £19.99 year → four passes cost more than a year.
        XCTAssertEqual(service.passesWorthUpgrading(passPrice: 4.99, annualPrice: 19.99), 5)
        XCTAssertEqual(service.passesWorthUpgrading(passPrice: 5.00, annualPrice: 20.00), 4)
        XCTAssertNil(service.passesWorthUpgrading(passPrice: 0, annualPrice: 19.99))
    }

    func testEveryProductIdentifierIsListed() {
        XCTAssertEqual(Set(ProductID.all).count, 3)
        XCTAssertTrue(ProductID.all.contains(ProductID.threeDayPass))
    }
}
