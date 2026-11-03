import AppIntents
import Foundation

// MARK: - Saying it out loud

/// What Siri says when asked what is due.
///
/// Pure, and built from the cached snapshot rather than a fetch: an answer
/// that waits on Canvas is an answer that arrives after you have stopped
/// listening, and one that fails without signal. The cache is written after
/// every successful refresh, so it is at worst a few hours old.
nonisolated enum CanvasSpeech {

    static func summary(for snapshot: CanvasSnapshot,
                        connected: Bool,
                        now: Date = Date(),
                        calendar: Calendar = .current) -> String {
        guard connected else {
            return "Canvas isn't connected. Open Tally and paste your access token to set it up."
        }

        guard !snapshot.classes.isEmpty else {
            return "I don't have any Canvas classes yet. Open Tally to load them."
        }

        let lines = snapshot.classes.map { subject -> String in
            guard let next = snapshot.outstanding(in: subject.id)
                .sorted(by: { $0.dueAt < $1.dueAt }).first
            else {
                return "\(subject.title) is clear"
            }

            let when = spokenWhen(
                CanvasDue.dayPhrase(for: next.dueAt, from: now, calendar: calendar)
            )
            return "for \(subject.title), \(next.name), \(when)"
        }

        return sentence(from: lines)
    }

    /// "due tonight", "due next Monday", "due Wednesday night" — and never
    /// "due overdue".
    ///
    /// Only the relative words get lowered. Lowering the first letter of
    /// everything turns a weekday into "due wednesday night" and a date into
    /// "due dec 15"; these four are the complete set of phrases `dayPhrase`
    /// can open with that are not proper nouns.
    private static func spokenWhen(_ phrase: String) -> String {
        guard phrase != "Overdue" else { return "which is overdue" }

        let lowerable = ["Tonight", "Today", "Tomorrow", "Next"]
        let opening = phrase.split(separator: " ").first.map(String.init) ?? phrase

        guard lowerable.contains(opening), let first = phrase.first else {
            return "due " + phrase
        }
        return "due " + first.lowercased() + phrase.dropFirst()
    }

    /// Each class gets its own sentence. Siri reads a full stop as a pause,
    /// which is what keeps two classes from running into each other.
    private static func sentence(from lines: [String]) -> String {
        lines
            .map { line in
                guard let first = line.first else { return line }
                return first.uppercased() + line.dropFirst() + "."
            }
            .joined(separator: " ")
    }
}

// MARK: - The intent

struct CanvasDueIntent: AppIntent {
    static var title: LocalizedStringResource = "What's due"

    static var description = IntentDescription(
        "Says the next unsubmitted assignment for each class."
    )

    /// Answers out loud without opening anything.
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Read straight off the disk cache and the Keychain rather than
        // through the engine: this can run with the app not launched, and
        // there is no reason to build the whole object graph to read one
        // file. Nothing here touches the network.
        let snapshot = CanvasCache.read() ?? CanvasSnapshot()
        let spoken = CanvasSpeech.summary(
            for: snapshot, connected: CanvasToken.isSaved
        )

        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}
