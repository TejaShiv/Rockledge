import CoreHaptics
import UIKit

final class GrainHaptics {
    var level: CGFloat = 0.6

    private var engine: CHHapticEngine?
    private let fallback = UIImpactFeedbackGenerator(style: .heavy)

    private var supported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    init() {
        fallback.prepare()
        buildEngine()
    }

    private func buildEngine() {
        guard supported else { return }
        do {
            let created = try CHHapticEngine()
            created.isAutoShutdownEnabled = true
            created.playsHapticsOnly = true
            created.resetHandler = { [weak self] in try? self?.engine?.start() }
            try created.start()
            engine = created
        } catch {
            engine = nil
        }
    }

    // MARK: Public

    /// Single sharp tick.
    func strike() {
        play(intensity: Float(0.16 + 0.84 * level), sharpness: Float(0.5 + 0.5 * level))
    }

    /// Low heavy thud, for the hold countdown.
    func thud(step: Int) {
        let ramp = min(Float(step) / 3.0, 1.0)
        play(intensity: 0.7 + ramp * 0.3, sharpness: 0.12 + ramp * 0.18)
    }

    /// Two hits back to back, for commits.
    func commit() {
        guard let engine else {
            fallback.impactOccurred(intensity: 1.0)
            return
        }
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0.07
            )
        ]
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? engine.start()
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    func soft() {
        play(intensity: 0.45, sharpness: 0.4)
    }

    private func play(intensity: Float, sharpness: Float) {
        guard let engine else {
            fallback.impactOccurred(intensity: CGFloat(intensity))
            return
        }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? engine.start()
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
