import CoreMotion
import SwiftUI

@Observable
final class MotionTilt {
    var roll: Double = 0
    var pitch: Double = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let targetRoll = max(-1, min(1, motion.attitude.roll / (.pi / 3.2)))
            let targetPitch = max(-1, min(1, (motion.attitude.pitch - 0.55) / (.pi / 3.2)))

            self.roll += (targetRoll - self.roll) * 0.20
            self.pitch += (targetPitch - self.pitch) * 0.20
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

// MARK: - Shapes

struct Polygon: Shape {
    let sides: Int
    var turn: Double = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for index in 0..<sides {
            let angle = Double(index) / Double(sides) * 2 * .pi - .pi / 2 + turn * .pi / 180
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
