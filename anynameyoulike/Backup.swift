import Foundation

/// Export and import of the whole document.
///
/// A signing certificate change hands the app a new container and the old
/// kalla.json goes with the old one. On a free Personal Team that happens
/// every seven days, and an exported copy is the only way back.
nonisolated enum Backup {

    /// Why an import was refused. Each case says what to do about it.
    enum Fault: LocalizedError, Equatable {
        case unreadable
        case notADocument
        case tooNew(found: Int, understood: Int)
        case corrupt

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file could not be read."
            case .notADocument:
                return "That is not a kalla.json. A backup has a version number in it."
            case .tooNew(let found, let understood):
                return """
                    That backup was written by a newer version of the app \
                    (document version \(found), this build understands \
                    \(understood)). Update the app and try again.
                    """
            case .corrupt:
                return "That backup is damaged and could not be read."
            }
        }
    }

    /// What an incoming file holds, so the confirmation can say what is about
    /// to replace what.
    struct Summary: Equatable {
        var groceryItems: Int
        var useLog: Int
        var people: Int
        var stepBatches: Int
        var savedAt: Date?

        var lines: [String] {
            [
                "\(groceryItems) grocery \(groceryItems == 1 ? "item" : "items")",
                "\(useLog) use \(useLog == 1 ? "entry" : "entries")",
                "\(people) in the trash rota",
                "\(stepBatches) step \(stepBatches == 1 ? "batch" : "batches")",
            ]
        }

        init(_ document: Store.Document) {
            groceryItems = document.groceryItems.count
            useLog = document.useLog.count
            people = document.trashRota.people.count
            stepBatches = document.stepLedger.count
            savedAt = document.savedAt
        }
    }

    // MARK: Export

    /// A dated copy to hand to the share sheet.
    ///
    /// Copied rather than shared in place: the live file can be rewritten by
    /// any part of the app while the sheet is open, and the name says what it
    /// is and when it came from once it is sitting in a Files folder.
    static func exportFile() throws -> URL {
        let document = Store.document

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalla-\(stamp.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Import

    /// Reads a file and checks it before anything is overwritten.
    static func inspect(_ url: URL) throws -> Store.Document {
        // A file handed over by the document picker lives outside the
        // sandbox until this is asked for.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw Fault.unreadable }
        return try inspect(data)
    }

    /// The version is read from the raw JSON rather than from a decoded
    /// document. Decoding is deliberately forgiving — a document missing a
    /// key just gets an empty one — so any JSON object at all would come back
    /// as a valid, empty document and quietly wipe everything. Insisting on a
    /// version number up front is what makes this safe.
    static func inspect(_ data: Data) throws -> Store.Document {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any]
        else { throw Fault.notADocument }

        guard let version = (object["version"] as? NSNumber)?.intValue else {
            throw Fault.notADocument
        }
        guard version <= Store.currentVersion else {
            throw Fault.tooNew(found: version, understood: Store.currentVersion)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(Store.Document.self, from: data) else {
            throw Fault.corrupt
        }

        return repaired(document)
    }

    /// Straightens out anything that would be an invalid state in the app
    /// even though it decoded. A hand-edited file is a supported way to use
    /// this document, so it will not always be internally consistent.
    static func repaired(_ document: Store.Document) -> Store.Document {
        var fixed = document

        // An empty rota has nobody to take the bins out, and an index into it
        // that points nowhere would show the wrong person as "you".
        if fixed.trashRota.people.isEmpty {
            fixed.trashRota.people = ["Me"]
        }
        if !fixed.trashRota.people.indices.contains(fixed.trashRota.me) {
            fixed.trashRota.me = 0
        }

        // Quantities that are not real numbers propagate into every rate and
        // forecast and turn the grocery screen into NaN.
        fixed.groceryItems = fixed.groceryItems.filter {
            $0.packSize.isFinite && $0.remaining.isFinite
                && $0.startRate.isFinite && $0.tare.isFinite
        }
        fixed.useLog = fixed.useLog.filter { $0.amount.isFinite }

        return fixed
    }

    // MARK: Rolling local snapshots

    /// One dated copy a day, inside Documents.
    ///
    /// These are a safety net for a bad import or a half-written file. They
    /// are NOT protection against re-signing: the snapshots sit in the same
    /// container as kalla.json and go with it. Only an exported copy that
    /// left the phone survives that.
    enum Snapshots {
        static let folderName = "snapshots"
        static let keep = 7

        static var folder: URL {
            Store.folder.appendingPathComponent(folderName, isDirectory: true)
        }

        /// Newest first.
        static func all() -> [URL] {
            let found = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []

            return found
                .filter { $0.pathExtension == "json" }
                .sorted { takenAt($0) > takenAt($1) }
        }

        static func takenAt(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
        }

        /// Writes one if the newest is more than a day old, then drops the
        /// oldest beyond the limit. Called on launch; cheap when it is a no-op.
        @discardableResult
        static func writeIfDue(now: Date = Date()) -> URL? {
            let existing = all()

            if let newest = existing.first,
               now.timeIntervalSince(takenAt(newest)) < 24 * 60 * 60 {
                return nil
            }

            try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true
            )

            let stamp = DateFormatter()
            stamp.dateFormat = "yyyy-MM-dd-HHmm"
            let url = folder.appendingPathComponent("kalla-\(stamp.string(from: now)).json")

            guard let data = try? Data(contentsOf: Store.url),
                  (try? data.write(to: url, options: .atomic)) != nil
            else { return nil }

            prune()
            return url
        }

        static func prune() {
            for old in all().dropFirst(keep) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    /// Overwrites everything. Only call once the user has said yes.
    static func restore(_ document: Store.Document) {
        Store.replace(with: document)
    }
}
