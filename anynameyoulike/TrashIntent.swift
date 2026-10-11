import AppIntents
import Foundation

/// "Whose turn is it" — answered for the same week the card is showing, so
/// the spoken answer and the screen cannot disagree.
struct WhoseTurnIntent: AppIntent {
    static var title: LocalizedStringResource = "Whose turn for the bins"
    static var description = IntentDescription(
        "Says whose bins are next out."
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Read through rather than from a cached engine: this runs from the
        // lock screen with the app not necessarily started.
        let rota = TrashRota.load()
        return .result(dialog: IntentDialog(stringLiteral: rota.spokenTurn()))
    }
}
