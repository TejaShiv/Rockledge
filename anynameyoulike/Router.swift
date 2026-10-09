import Foundation

/// Where a notification tap should land.
///
/// The delegate runs before any view is on screen, so the intent is parked
/// here and the first screen to come up picks it off.
@Observable
final class Router {
    enum Destination: Equatable {
        /// Straight to choosing where the exported file goes.
        case export
    }

    var pending: Destination?

    func take() -> Destination? {
        defer { pending = nil }
        return pending
    }
}
