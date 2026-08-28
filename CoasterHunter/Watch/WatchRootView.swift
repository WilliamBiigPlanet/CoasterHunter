import SwiftUI
import CoasterHunterCore

/// The watch face of the app.
///
/// The phone is in a locker — that is the whole premise — so this has to work
/// standalone, be readable at a glance with the ride still moving, and take one
/// tap to log. Nothing here waits on the phone.
struct WatchRootView: View {
    @StateObject private var model = WatchModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.phase {
            case .waiting:  waitingView
            case .riding:   ridingView
            case .finished: finishedView
            }
        }
    }

    private var waitingView: some View {
        VStack(spacing: 6) {
            Text(model.parkName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.6))

            Text("\(model.lapsToday)")
                .font(.system(size: 48, weight: .ultraLight))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text("LAPS TODAY")
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.55))

            Button("Log a lap") { model.logManually() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.gForce)
                .padding(.top, 6)
        }
        .padding()
    }

    private var ridingView: some View {
        VStack(spacing: 4) {
            Text("RECORDING")
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(Palette.gForce)
            Text(model.attractionName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 4)
        }
        .padding()
    }

    private var finishedView: some View {
        VStack(spacing: 5) {
            Text(model.attractionName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.airtimeText)
                    .font(.system(size: 40, weight: .ultraLight))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("s").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
            }

            Text(model.summaryLine)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 5) {
                Button("Log") { model.confirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.gForce)
                Button("Not me") { model.discard() }
                    .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.top, 4)
        }
        .padding()
    }
}

@MainActor
final class WatchModel: ObservableObject {
    enum Phase { case waiting, riding, finished }

    @Published var phase: Phase = .waiting
    @Published var parkName = "Alton Towers"
    @Published var attractionName = "Wicker Man"
    @Published var lapsToday = 11
    @Published var metrics: LapMetrics?

    var airtimeText: String {
        String(format: "%.1f", metrics?.sustainedAirtimeSeconds ?? 0)
    }

    var summaryLine: String {
        guard let metrics else { return "AIRTIME" }
        return "AIRTIME · PEAK \(String(format: "%.1f", metrics.peakVerticalG)) G"
    }

    func logManually() {
        lapsToday += 1
    }

    func confirm() {
        lapsToday += 1
        phase = .waiting
    }

    func discard() {
        phase = .waiting
    }
}
