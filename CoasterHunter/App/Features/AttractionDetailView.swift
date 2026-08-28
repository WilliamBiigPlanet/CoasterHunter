import SwiftUI
import CoasterHunterCore

/// The spec sheet, plus the two things a database alone cannot show: what the
/// community has actually measured, and how many times you have ridden it.
struct AttractionDetailView: View {
    @Environment(\.colorScheme) private var scheme

    let attraction: Attraction
    let spec: AttractionSpec?
    let lapCount: Int
    let firstRidden: Date?

    var body: some View {
        ZStack {
            DotGridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.tileGap) {
                    header
                    tallyCard
                    specGrid
                    if spec?.heightRestrictionCm != nil { riderInfo }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 90)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                EyebrowLabel(subtitle)
                Text(attraction.name)
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.ink(scheme))
            }
            Spacer()
            CircleIconButton(systemName: "star") {}
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }

    private var subtitle: String {
        [spec?.manufacturer, spec?.model, spec?.openedYear.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var tallyCard: some View {
        SquircleCard {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel("Your tally")
                    Text("\(lapCount)")
                        .font(Typography.statValue(34))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink(scheme))
                }
                if let firstRidden {
                    Text("laps since \(firstRidden.formatted(.dateTime.year()))\nfirst ridden \(firstRidden.formatted(date: .abbreviated, time: .omitted))")
                        .font(Typography.label)
                        .foregroundStyle(Palette.inkTertiary(scheme))
                }
                Spacer()
            }
        }
    }

    /// Only shows the fields the sources actually filled. A grid of dashes
    /// would tell the rider nothing and make the data look worse than it is.
    private var specGrid: some View {
        let entries = availableSpecs
        return VStack(spacing: Metrics.tileGap) {
            ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { index in
                HStack(spacing: Metrics.tileGap) {
                    StatTile(
                        key: entries[index].key,
                        value: entries[index].value,
                        unit: entries[index].unit)
                    if index + 1 < entries.count {
                        StatTile(
                            key: entries[index + 1].key,
                            value: entries[index + 1].value,
                            unit: entries[index + 1].unit)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private struct SpecEntry {
        let key: String
        let value: String
        let unit: String?
    }

    private var availableSpecs: [SpecEntry] {
        guard let spec else { return [] }
        var entries: [SpecEntry] = []

        if let height = spec.heightMetres {
            entries.append(.init(key: "Height", value: format(height), unit: "m"))
        }
        if let drop = spec.dropMetres {
            entries.append(.init(key: "Drop", value: format(drop), unit: "m"))
        }
        if let speed = spec.speedKmh {
            entries.append(.init(key: "Top speed", value: format(speed), unit: "km/h"))
        }
        if let length = spec.lengthMetres {
            entries.append(.init(key: "Length", value: format(length), unit: "m"))
        }
        if let inversions = spec.inversions {
            entries.append(.init(key: "Inversions", value: "\(inversions)", unit: nil))
        }
        if let duration = spec.durationSeconds {
            entries.append(.init(key: "Duration", value: "\(duration)", unit: "s"))
        }
        if let gForce = spec.maxGForce {
            entries.append(.init(key: "Max G", value: format(gForce), unit: "g"))
        }
        if let angle = spec.maxAngleDegrees {
            entries.append(.init(key: "Steepest", value: format(angle), unit: "°"))
        }
        return entries
    }

    private var riderInfo: some View {
        SquircleCard(radius: Metrics.tileRadius, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Before you queue")
                if let cm = spec?.heightRestrictionCm {
                    infoRow("Minimum height", "\(cm) cm")
                }
                if let rows = spec?.rowCount {
                    infoRow("Rows", "\(rows)")
                }
            }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkSecondary(scheme))
            Spacer()
            Text(value)
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.ink(scheme))
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
