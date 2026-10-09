import Foundation

/// Long-lived engines, shared across every screen.
enum Shared {
    static let motion = MotionTilt()
    static let haptics = GrainHaptics()
    static let heart = HeartMonitor()
    static let sleep = SleepMonitor()
    static let pantry = Pantry()
    static let transit = Transit()
    static let router = Router()
}
