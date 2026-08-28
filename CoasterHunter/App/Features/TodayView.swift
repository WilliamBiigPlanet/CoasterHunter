import SwiftUI
import CoasterHunterCore

/// The in-park home screen.
///
/// One number owns the screen — airtime banked today — because a screen full of
/// equally-weighted stats is a screen nobody reads while walking between rides.
struct TodayView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var store: StoreService
    @StateObject private var model = TodayModel()

    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            DotGridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.tileGap) {
                    header
                    airtimeTile
                    counters
                    if let message = store.passStatusMessage { passBanner(message) }
                    lapList
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                EyebrowLabel(model.checkInSummary)
                Text(model.parkName)
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.ink(scheme))
            }
            Spacer()
            CircleIconButton(systemName: "line.3.horizontal") {}
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }

    private var airtimeTile: some View {
        MeshHeroTile(gradient: MeshGradient.air) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AIRTIME TODAY")
                    .font(Typography.label)
                    .kerning(1.4)
                    .opacity(0.82)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    DotMatrixNumeral(model.airtimeText, size: 50)
                    Text("s").font(Typography.statValue(18)).opacity(0.75)
                }

                Text(model.bestLapSummary)
                    .font(Typography.caption)
                    .opacity(0.85)
            }
        }
    }

    private var counters: some View {
        HStack(spacing: Metrics.tileGap) {
            StatTile(
                key: "Laps", value: "\(model.lapCount)",
                delta: model.lapDelta, deltaIsGood: true)
            StatTile(
                key: "Steps", value: model.stepsText,
                delta: model.distanceText, deltaIsGood: true)
        }
    }

    private func passBanner(_ message: String) -> some View {
        SquircleCard(radius: 16, padding: 11) {
            HStack(spacing: 9) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.heat)
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary(scheme))
                Spacer(minLength: 4)
                if store.dormantPass != nil, store.tier == .free {
                    Button("Start") { store.activatePass() }
                        .font(Typography.label)
                        .foregroundStyle(Palette.gForce)
                }
            }
        }
    }

    @ViewBuilder
    private var lapList: some View {
        EyebrowLabel("Today's laps")
            .padding(.horizontal, 4)
            .padding(.top, 6)

        if model.laps.isEmpty {
            SquircleCard {
                Text("No laps yet. Log one from your watch, or tap a ride to log it here.")
                    .font(Typography.bodyText)
                    .foregroundStyle(Palette.inkTertiary(scheme))
            }
        } else {
            ForEach(model.laps) { entry in
                AttractionRow(name: entry.name, detail: entry.detail, accent: entry.accent)
            }
        }

        if !store.hasProFeatures, model.trackedLapsToday >= FreeTierLimits.sensorTrackedLapsPerDay {
            Button { showingPaywall = true } label: {
                SquircleCard(radius: 16, padding: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You've used today's \(FreeTierLimits.sensorTrackedLapsPerDay) tracked laps")
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.ink(scheme))
                        Text("Laps still log without tracking. Go Pro or grab a 3-Day Pass to measure them all.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkTertiary(scheme))
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Screen state. Sample values until the data layer lands — the shape is what
/// the view is built against, so swapping the source does not disturb the view.
final class TodayModel: ObservableObject {
    struct LapEntry: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let accent: Color
    }

    @Published var parkName = "Alton Towers"
    @Published var checkInSummary = "Checked in · 4h 12m"
    @Published var airtimeSeconds: Double = 14.2
    @Published var lapCount = 11
    @Published var trackedLapsToday = 3
    @Published var steps = 18_412
    @Published var distanceMetres: Double = 12_400
    @Published var bestLapSummary = "Best lap · Wicker Man, back row"

    @Published var laps: [LapEntry] = [
        .init(name: "Nemesis Reborn", detail: "3 laps · 3.9 G", accent: Palette.gForce),
        .init(name: "Wicker Man", detail: "4 laps · 5.1 s air", accent: Palette.airtime),
        .init(name: "The Smiler", detail: "2 laps · 14 inv", accent: Palette.track),
    ]

    var airtimeText: String { String(format: "%.1f", airtimeSeconds) }
    var lapDelta: String? { "+4 vs avg" }
    var stepsText: String { steps.formatted(.number.grouping(.automatic)) }
    var distanceText: String { String(format: "%.1f km", distanceMetres / 1000) }
}
