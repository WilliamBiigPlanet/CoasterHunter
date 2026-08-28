import SwiftUI
import CoasterHunterCore

/// The app shell.
///
/// `preferredColorScheme(nil)` is what makes the System option work — it hands
/// the decision back to the OS rather than picking one. That is the default and
/// the case most people will be in, so it is the one to get right.
struct RootView: View {
    @StateObject private var appearanceStore = AppearanceStore()
    @StateObject private var store = StoreService()

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle") }

            SearchView()
                .tabItem { Label("Parks", systemImage: "map") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(appearanceStore)
        .environmentObject(store)
        .preferredColorScheme(appearanceStore.appearance.colorScheme)
        .tint(Palette.gForce)
        .task { await store.start() }
    }
}

/// Placeholder until the seed database is wired in.
struct SearchView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""

    var body: some View {
        ZStack {
            DotGridBackground()
            VStack(alignment: .leading, spacing: Metrics.tileGap) {
                Text("Parks")
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.ink(scheme))
                    .padding(.horizontal, 4)

                SquircleCard {
                    Text("198 parks and 8,229 attractions ship with the app. "
                         + "Search lands once the seed database is wired in.")
                        .font(Typography.bodyText)
                        .foregroundStyle(Palette.inkTertiary(scheme))
                }
                Spacer()
            }
            .padding(Metrics.gutter)
        }
    }
}
