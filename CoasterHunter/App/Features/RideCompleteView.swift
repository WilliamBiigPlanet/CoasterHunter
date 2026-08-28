import SwiftUI
import CoasterHunterCore

/// What the rider sees when a lap lands from the watch.
struct RideCompleteView: View {
    @Environment(\.colorScheme) private var scheme

    let attractionName: String
    let context: String
    let trace: RideTrace

    private var metrics: LapMetrics? { MetricsCalculator.metrics(for: trace) }

    var body: some View {
        ZStack {
            DotGridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.tileGap) {
                    header
                    scoreTile
                    traceCard
                    metricGrid
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 90)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                EyebrowLabel(context)
                Text(attractionName)
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.ink(scheme))
            }
            Spacer()
            CircleIconButton(systemName: "square.and.arrow.up") {}
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }

    private var scoreTile: some View {
        MeshHeroTile(gradient: MeshGradient.thrill) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RIDE SCORE")
                    .font(Typography.label)
                    .kerning(1.4)
                    .opacity(0.82)
                DotMatrixNumeral("\(metrics?.rideScore ?? 0)", size: 50)
                Text(scoreCaption)
                    .font(Typography.caption)
                    .opacity(0.85)
            }
        }
    }

    private var traceCard: some View {
        SquircleCard(radius: Metrics.tileRadius, padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("RIDEDNA · VERTICAL G OVER \(Int(trace.duration)) S")
                    .font(Typography.label)
                    .kerning(0.6)
                    .foregroundStyle(Palette.inkTertiary(scheme))
                RideDNAView(trace: trace)
                RideDNALegend()
            }
        }
    }

    private var metricGrid: some View {
        VStack(spacing: Metrics.tileGap) {
            HStack(spacing: Metrics.tileGap) {
                StatTile(key: "Peak G", value: format(metrics?.peakVerticalG), unit: "g")
                StatTile(key: "Airtime", value: format(metrics?.sustainedAirtimeSeconds), unit: "s")
            }
            HStack(spacing: Metrics.tileGap) {
                StatTile(key: "Inversions", value: "\(metrics?.inversions ?? 0)")
                StatTile(key: "Roughness", value: format(metrics?.roughnessIndex), unit: "/10")
            }
        }
    }

    private var scoreCaption: String {
        guard let metrics else { return "No sensor data for this lap" }
        if metrics.sustainedAirtimeSeconds >= 4 { return "An airtime machine" }
        if metrics.inversions >= 5 { return "Relentless — \(metrics.inversions) inversions" }
        if metrics.peakVerticalG >= 4 { return "Heavy positive g through the pullouts" }
        return "\(metrics.airtimeMoments) airtime moments"
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }
}
