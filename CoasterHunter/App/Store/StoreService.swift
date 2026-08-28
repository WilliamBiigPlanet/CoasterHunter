import Foundation
import StoreKit
import CoasterHunterCore

/// Purchasing and entitlement state.
///
/// The 3-Day Park Pass is a non-renewing subscription, which Apple does not
/// track an expiry for — that clock is ours, and it lives in
/// `EntitlementService` where it is unit-tested. This type's job is to turn
/// StoreKit transactions into the `Entitlements` value that service reads.
@MainActor
public final class StoreService: ObservableObject {

    @Published public private(set) var products: [Product] = []
    @Published public private(set) var entitlements = Entitlements()
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: String?

    private let service = EntitlementService()
    private var updatesTask: Task<Void, Never>?

    private static let passesKey = "parkPasses"

    public init() {
        entitlements.passes = Self.loadPasses()
    }

    deinit { updatesTask?.cancel() }

    public var tier: Tier { service.tier(for: entitlements) }
    public var hasProFeatures: Bool { service.hasProFeatures(entitlements) }
    public var passStatusMessage: String? { service.passStatusMessage(for: entitlements) }
    public var dormantPass: ParkPass? { service.dormantPass(in: entitlements) }

    // MARK: Lifecycle

    public func start() async {
        await loadProducts()
        await refreshEntitlements()
        listenForTransactions()
    }

    public func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            // Pass first, then annual, then lifetime — cheapest commitment first.
            products = loaded.sorted { lhs, rhs in
                order(of: lhs.id) < order(of: rhs.id)
            }
        } catch {
            lastError = "Couldn't load prices. Check your connection and try again."
        }
    }

    private func order(of id: String) -> Int {
        switch id {
        case ProductID.threeDayPass: return 0
        case ProductID.annual:       return 1
        case ProductID.lifetime:     return 2
        default:                     return 3
        }
    }

    // MARK: Purchasing

    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = try? verification.payloadValue else {
                    lastError = "That purchase couldn't be verified."
                    return false
                }
                await apply(transaction)
                await transaction.finish()
                return true

            case .userCancelled:
                return false

            case .pending:
                lastError = "Purchase pending approval."
                return false

            @unknown default:
                return false
            }
        } catch {
            lastError = "Purchase failed. You haven't been charged."
            return false
        }
    }

    public func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Couldn't restore purchases."
        }
    }

    // MARK: Park pass

    /// Start a dormant pass. Called from the paywall and on park check-in.
    public func activatePass() {
        entitlements = service.activatingPass(in: entitlements)
        Self.savePasses(entitlements.passes)
    }

    public func checkedIntoPark() {
        entitlements = service.onCheckIn(entitlements)
        Self.savePasses(entitlements.passes)
    }

    // MARK: Transactions

    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let transaction = try? update.payloadValue else { continue }
                await self?.apply(transaction)
                await transaction.finish()
            }
        }
    }

    public func refreshEntitlements() async {
        var refreshed = Entitlements(passes: entitlements.passes)

        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? entitlement.payloadValue else { continue }
            switch transaction.productID {
            case ProductID.lifetime:
                refreshed.hasLifetime = true
            case ProductID.annual:
                refreshed.subscriptionExpiresAt = transaction.expirationDate
            default:
                break
            }
        }

        entitlements = refreshed
    }

    private func apply(_ transaction: Transaction) async {
        switch transaction.productID {
        case ProductID.lifetime:
            entitlements.hasLifetime = true

        case ProductID.annual:
            entitlements.subscriptionExpiresAt = transaction.expirationDate

        case ProductID.threeDayPass:
            // Non-renewing subscriptions stay in `currentEntitlements` forever,
            // so we record each purchase once by its transaction id rather than
            // re-adding a pass on every refresh.
            let id = UUID(uuidString: String(format: "%032llx", transaction.id))
                ?? UUID()
            if !entitlements.passes.contains(where: { $0.id == id }) {
                entitlements.passes.append(
                    ParkPass(id: id, purchasedAt: transaction.purchaseDate))
                Self.savePasses(entitlements.passes)
            }

        default:
            break
        }
    }

    // MARK: Persistence
    //
    // Local only for now. Passes move to the Supabase account so they restore
    // across devices — Apple will not do that for a non-renewing subscription.

    private static func loadPasses() -> [ParkPass] {
        guard let data = UserDefaults.standard.data(forKey: passesKey),
              let passes = try? JSONDecoder().decode([ParkPass].self, from: data)
        else { return [] }
        return passes
    }

    private static func savePasses(_ passes: [ParkPass]) {
        guard let data = try? JSONEncoder().encode(passes) else { return }
        UserDefaults.standard.set(data, forKey: passesKey)
    }
}
