import Foundation

// MARK: - Model

/// One item and how much of it a meal uses.
nonisolated struct MealPortion: Codable, Identifiable, Equatable {
    var id = UUID()
    var itemID: UUID
    var amount: Double
}

/// A named set of portions: "lunch" is 250g chicken and 4 slices of bread.
///
/// Kept separate from the items themselves because meals change far more
/// often than the pantry does.
nonisolated struct Meal: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var portions: [MealPortion] = []

    /// What Siri matches on, and what the rows are sorted by.
    var spokenName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - What happened when one was logged

/// The result of logging a meal, in enough detail to be read aloud.
nonisolated struct MealOutcome {
    struct Line: Equatable {
        var name: String
        var taken: Double
        var short: Double
        var unit: String

        var ranOut: Bool { short > 0 }
    }

    var meal: String
    var lines: [Line] = []

    var logged: [Line] { lines.filter { $0.taken > 0 } }
    var ranOut: [Line] { lines.filter(\.ranOut) }

    /// Reads as a sentence, because Siri says it out loud.
    ///
    /// Names what came off so the deduction can be checked without opening
    /// the app, and names anything that ran out, since that is the part worth
    /// interrupting someone for.
    var spoken: String {
        guard !lines.isEmpty else {
            return "\(meal) has nothing in it yet."
        }
        guard !logged.isEmpty else {
            return "Nothing left for \(meal). \(shortfallSentence)"
        }

        var sentence = "Logged \(list(logged.map(detail)))."
        if !ranOut.isEmpty {
            sentence += " \(shortfallSentence)"
        }
        return sentence
    }

    private var shortfallSentence: String {
        let names = list(ranOut.map(\.name))
        return ranOut.count == 1
            ? "\(names) ran out."
            : "\(names) ran out."
    }

    private func detail(_ line: Line) -> String {
        "\(Self.trim(line.taken)) \(line.unit) of \(line.name)"
    }

    /// "a", "a and b", "a, b and c" — spoken lists do not take a comma
    /// before the last item.
    private func list(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return "\(parts.dropLast().joined(separator: ", ")) and \(parts.last!)"
        }
    }

    static func trim(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
