import Foundation
import CoasterHunterCore

#if os(watchOS) || os(iOS)
import CoreMotion

/// The CoreMotion binding.
///
/// Deliberately thin: it starts and stops the sensors and forwards samples to
/// `RideCaptureSession`, which owns every decision and is unit-tested. Anything
/// that needed judgement was moved out of here on purpose, because this file
/// cannot be tested without a wrist.
@MainActor
public final class MotionCapture: ObservableObject {

    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastTrace: RideTrace?
    @Published public private(set) var lastMetrics: LapMetrics?

    /// Full rate while a ride is underway. `CMDeviceMotion` has already
    /// separated gravity from user acceleration, which is what makes inversion
    /// detection possible.
    private let activeInterval = 1.0 / 100
    /// Idle rate. Enough to notice a ride starting, cheap enough to leave on all
    /// day inside a park geofence.
    private let idleInterval = 1.0 / 20

    private let manager = CMMotionManager()
    private var session = RideCaptureSession()
    private var startedAt: Date?

    public init() {}

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Begin watching. Call on park check-in, not on app launch — sampling
    /// outside a park is pure battery cost for no possible lap.
    public func startMonitoring() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }

        session.reset()
        startedAt = Date()
        manager.deviceMotionUpdateInterval = idleInterval

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    public func stopMonitoring() {
        manager.stopDeviceMotionUpdates()
        session.reset()
        isCapturing = false
    }

    /// Discard the lap in progress — the rider says it wasn't a ride.
    public func cancelCurrentCapture() {
        session.reset()
        isCapturing = false
        adjustRate(for: .idle)
    }

    private func handle(_ motion: CMDeviceMotion) {
        guard let startedAt else { return }

        let sample = MotionSample(
            time: Date().timeIntervalSince(startedAt),
            // Watch axes: +Y runs up through the wrist, so vertical load is the
            // Y component with gravity added back in.
            verticalG: motion.userAcceleration.y + motion.gravity.y * -1,
            lateralG: motion.userAcceleration.x,
            longitudinalG: motion.userAcceleration.z,
            gravityX: motion.gravity.x,
            gravityY: -motion.gravity.y,
            gravityZ: motion.gravity.z)

        let wasCapturing = session.state == .capturing
        let finished = session.ingest(sample)

        if session.state == .capturing, !wasCapturing {
            isCapturing = true
            adjustRate(for: .capturing)
        }

        if let finished {
            lastTrace = finished
            lastMetrics = MetricsCalculator.metrics(for: finished)
            isCapturing = false
            session = RideCaptureSession()
            adjustRate(for: .idle)
        }
    }

    private func adjustRate(for state: RideCaptureSession.State) {
        manager.deviceMotionUpdateInterval =
            state == .capturing ? activeInterval : idleInterval
    }
}
#endif
