import Foundation

/// One sample of device motion, in the rider's frame of reference.
///
/// Comes from `CMDeviceMotion` on watchOS, which has already separated gravity
/// from user acceleration via sensor fusion — that separation is what makes
/// inversion detection possible at all, so we take it rather than redo it.
///
/// Axes, with the watch worn normally on the wrist:
///   - `verticalG`   +1 at rest, 0 in freefall, negative when thrown upward.
///   - `lateralG`    sideways load, signed left/right.
///   - `longitudinalG` fore-aft load: launches and brake runs.
///   - `gravity*`    unit gravity vector in the device frame, for attitude.
public struct MotionSample: Codable, Hashable, Sendable {
    /// Seconds since the start of capture.
    public let time: Double
    public let verticalG: Double
    public let lateralG: Double
    public let longitudinalG: Double
    public let gravityX: Double
    public let gravityY: Double
    public let gravityZ: Double

    public init(
        time: Double, verticalG: Double, lateralG: Double = 0,
        longitudinalG: Double = 0,
        gravityX: Double = 0, gravityY: Double = -1, gravityZ: Double = 0
    ) {
        self.time = time
        self.verticalG = verticalG
        self.lateralG = lateralG
        self.longitudinalG = longitudinalG
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
    }

    /// Total load felt by the rider, ignoring direction.
    public var magnitudeG: Double {
        (verticalG * verticalG + lateralG * lateralG + longitudinalG * longitudinalG)
            .squareRoot()
    }

    /// How far the rider is from upright, in degrees. 0 upright, 180 inverted.
    ///
    /// Derived from where gravity points in the device frame. With the watch
    /// worn normally, -Y is "up" through the rider's head, so gravity along +Y
    /// means the rider is the right way up and along -Y means they are not.
    public var tiltDegrees: Double {
        let magnitude = (gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ)
            .squareRoot()
        guard magnitude > 0.001 else { return 0 }
        let cosine = max(-1, min(1, gravityY / magnitude))
        return acos(cosine) * 180 / .pi
    }
}

/// A complete capture of one lap.
public struct RideTrace: Codable, Hashable, Sendable {
    public let samples: [MotionSample]
    /// Nominal capture rate. Real rates wobble; the maths uses actual timestamps.
    public let sampleRateHz: Double
    public let startedAt: Date

    public init(samples: [MotionSample], sampleRateHz: Double = 100, startedAt: Date = Date()) {
        self.samples = samples
        self.sampleRateHz = sampleRateHz
        self.startedAt = startedAt
    }

    public var duration: Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.time - first.time
    }

    public var isEmpty: Bool { samples.count < 2 }

    /// Reduce to a fixed number of points for storage and display. Keeps the
    /// extremes of each bucket, so a downsampled trace still shows its peaks —
    /// averaging would flatten exactly the moments that matter.
    public func downsampled(to targetCount: Int) -> RideTrace {
        guard targetCount > 1, samples.count > targetCount else { return self }

        let bucketSize = Double(samples.count) / Double(targetCount)
        var picked: [MotionSample] = []
        picked.reserveCapacity(targetCount)

        for bucket in 0..<targetCount {
            let start = Int(Double(bucket) * bucketSize)
            let end = min(samples.count, max(start + 1, Int(Double(bucket + 1) * bucketSize)))
            let slice = samples[start..<end]

            // Whichever sample in the bucket deviates furthest from 1 g.
            let extreme = slice.max { abs($0.verticalG - 1) < abs($1.verticalG - 1) }
            if let extreme { picked.append(extreme) }
        }
        return RideTrace(samples: picked, sampleRateHz: sampleRateHz, startedAt: startedAt)
    }
}
