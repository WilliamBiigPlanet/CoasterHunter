import SwiftUI
import StoreKit
import CoasterHunterCore

/// The paywall.
///
/// Shows the three products with the upsell maths stated plainly — four passes
/// cost more than a year, and saying so is worth more than the handful of extra
/// pass sales that hiding it would win. Enthusiast communities compare notes.
struct PaywallView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService

    @State private var purchasing: String?

    var body: some View {
        ZStack {
            DotGridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    products
                    featureList
                    footnote
                }
                .padding(Metrics.gutter)
            }
        }
        .overlay(alignment: .topTrailing) {
            CircleIconButton(systemName: "xmark") { dismiss() }
                .padding(Metrics.gutter)
        }
        .task { await store.loadProducts() }
    }

    private var header: some View {
        MeshHeroTile(gradient: MeshGradient.thrill) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COASTERHUNTER PRO")
                    .font(Typography.label)
                    .kerning(1.4)
                    .opacity(0.85)
                Text("Measure every lap")
                    .font(Typography.hero(30))
                Text("Unlimited tracking, your full RideDNA archive, roughness, "
                     + "row-by-row telemetry and your ranked Top 100.")
                    .font(Typography.caption)
                    .opacity(0.9)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 44)
    }

    @ViewBuilder
    private var products: some View {
        if store.products.isEmpty {
            SquircleCard {
                Text(store.isLoading ? "Loading prices…" : "Prices unavailable right now.")
                    .font(Typography.bodyText)
                    .foregroundStyle(Palette.inkSecondary(scheme))
            }
        } else {
            VStack(spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    productRow(product)
                }
            }
        }
    }

    private func productRow(_ product: Product) -> some View {
        Button {
            Task {
                purchasing = product.id
                await store.purchase(product)
                purchasing = nil
            }
        } label: {
            SquircleCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title(for: product))
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.ink(scheme))
                        Text(subtitle(for: product))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary(scheme))
                    }
                    Spacer(minLength: 8)
                    if purchasing == product.id {
                        ProgressView()
                    } else {
                        Text(product.displayPrice)
                            .font(Typography.statValue(20))
                            .foregroundStyle(Palette.ink(scheme))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil)
    }

    private func title(for product: Product) -> String {
        switch product.id {
        case ProductID.threeDayPass: return "3-Day Park Pass"
        case ProductID.annual:       return "Pro — one year"
        case ProductID.lifetime:     return "Pro — lifetime"
        default:                     return product.displayName
        }
    }

    private func subtitle(for product: Product) -> String {
        switch product.id {
        case ProductID.threeDayPass:
            return "Everything in Pro for three days. Nothing to cancel."
        case ProductID.annual:
            return "14-day free trial. Renews yearly."
        case ProductID.lifetime:
            return "One payment, kept forever."
        default:
            return product.description
        }
    }

    private var featureList: some View {
        SquircleCard {
            VStack(alignment: .leading, spacing: 9) {
                EyebrowLabel("What you get")
                ForEach(ProFeature.allCases, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.airtimeText(scheme))
                            .padding(.top, 3)
                        Text(feature.title)
                            .font(Typography.bodyText)
                            .foregroundStyle(Palette.inkSecondary(scheme))
                    }
                }
            }
        }
    }

    /// The honest bit. Kept visible rather than buried in small print.
    @ViewBuilder
    private var footnote: some View {
        if let count = upsellCount {
            SquircleCard(padding: 12) {
                Text("Visiting more than \(count - 1) times a year? The annual "
                     + "works out cheaper than buying passes.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary(scheme))
            }
        }

        Button("Restore purchases") {
            Task { await store.restore() }
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.inkTertiary(scheme))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var upsellCount: Int? {
        guard
            let pass = store.products.first(where: { $0.id == ProductID.threeDayPass }),
            let annual = store.products.first(where: { $0.id == ProductID.annual })
        else { return nil }
        return EntitlementService().passesWorthUpgrading(
            passPrice: pass.price, annualPrice: annual.price)
    }
}
