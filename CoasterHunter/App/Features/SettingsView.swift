import SwiftUI
import CoasterHunterCore

struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var appearanceStore: AppearanceStore
    @EnvironmentObject private var store: StoreService

    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            DotGridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.tileGap) {
                    Text("Settings")
                        .font(Typography.screenTitle)
                        .foregroundStyle(Palette.ink(scheme))
                        .padding(.horizontal, 4)
                        .padding(.top, 4)

                    appearanceCard
                    subscriptionCard
                    attributionCard
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }

    private var appearanceCard: some View {
        SquircleCard {
            VStack(alignment: .leading, spacing: 9) {
                EyebrowLabel("Appearance")
                AppearancePicker(selection: $appearanceStore.appearance)
                Text(appearanceStore.appearance == .system
                     ? "Following your phone's setting."
                     : "Always \(appearanceStore.appearance.title.lowercased()), whatever your phone does.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary(scheme))
            }
        }
    }

    private var subscriptionCard: some View {
        SquircleCard {
            VStack(alignment: .leading, spacing: 9) {
                EyebrowLabel("Subscription")

                HStack {
                    Text(tierTitle)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.ink(scheme))
                    Spacer()
                    if store.tier == .free {
                        Button("Upgrade") { showingPaywall = true }
                            .font(Typography.label)
                            .foregroundStyle(Palette.gForce)
                    }
                }

                if let message = store.passStatusMessage {
                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary(scheme))
                }

                if store.dormantPass != nil, store.tier == .free {
                    Button("Start my 3-Day Pass") { store.activatePass() }
                        .font(Typography.caption)
                        .foregroundStyle(Palette.gForce)
                }
            }
        }
    }

    private var tierTitle: String {
        switch store.tier {
        case .free: return "Free"
        case .pass: return "3-Day Park Pass"
        case .pro:  return "Pro"
        }
    }

    /// Required by the data licences, and the right thing regardless — the
    /// database exists because volunteers built it.
    private var attributionCard: some View {
        SquircleCard {
            VStack(alignment: .leading, spacing: 7) {
                EyebrowLabel("Data sources")
                ForEach(DataAttribution.all, id: \.name) { source in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.name)
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.ink(scheme))
                        Text(source.licence)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary(scheme))
                    }
                }
                Text("Powered by Queue-Times.com")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary(scheme))
                    .padding(.top, 2)
            }
        }
    }
}

/// The attribution the free sources require of us.
enum DataAttribution {
    struct Source {
        let name: String
        let licence: String
    }

    static let all: [Source] = [
        .init(name: "ThemeParks.wiki", licence: "Free API — park and attraction data"),
        .init(name: "Wikipedia", licence: "CC BY-SA 4.0 — ride specifications"),
        .init(name: "Wikidata", licence: "CC0 1.0 — cross-references"),
        .init(name: "Queue-Times.com", licence: "Free API — live wait times"),
    ]
}
