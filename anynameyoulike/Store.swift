//
//  Store.swift
//  anynameyoulike
//
//  Created by Tejas Shivaprasad on 10/4/26.
//


import Foundation
import Synchronization

/// Everything durable lives in one JSON file in Documents, so it is visible
/// in the Files app, editable by hand, and included in device backups.
///
/// Preferences — reminder toggles and times — stay in UserDefaults. They are
/// settings rather than records, and nothing is lost if they reset.
///
/// Safe to reach from any actor. The cache lives inside a lock rather than
/// beside one, so there is no way to touch it without holding the lock.
nonisolated enum Store {
    static let fileName = "kalla.json"

    /// Bumped when the document's shape changes in a way an older build
    /// could not read. Import refuses anything above this.
    static let currentVersion = 1

    private static let migratedKey = "storeMigratedV2"

    /// Holds the loaded document, or nil before the first read.
    private static let cache = Mutex<Document?>(nil)

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var url: URL { folder.appendingPathComponent(fileName) }

    // MARK: The document

    /// One top-level object. Keys decode independently, so a hand-edited file
    /// that is missing a section still opens, with that section empty.
    struct Document: Codable {
        var version = Store.currentVersion
        var savedAt = Date()
        var groceryItems: [GroceryItem] = []
        var useLog: [UseEntry] = []
        var trashRota = TrashRota()
        var stepLedger: [WriteBatch] = []
        var transit = TransitSnapshot()

        /// The home card's own arrivals. Separate from `transit`, which
        /// follows whatever stop the dashboard last resolved.
        var transitHome = TransitSnapshot()

        init() {}

        enum CodingKeys: String, CodingKey {
            case version, savedAt, groceryItems, useLog, trashRota, stepLedger
            case transit, transitHome
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
                ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
            }

            version = value(.version, Store.currentVersion)
            savedAt = value(.savedAt, Date())
            groceryItems = value(.groceryItems, [])
            useLog = value(.useLog, [])
            trashRota = value(.trashRota, TrashRota())
            stepLedger = value(.stepLedger, [])
            transit = value(.transit, TransitSnapshot())
            transitHome = value(.transitHome, TransitSnapshot())
        }
    }

    // MARK: Read and write

    /// Cached, so repeated reads in one session do not touch the disk.
    static var document: Document {
        cache.withLock { loaded(&$0) }
    }

    /// The only way to change anything: edit the document, then write it whole.
    ///
    /// The whole read-modify-write runs under the lock, the file included, so
    /// concurrent callers cannot lose one another's changes and the file never
    /// lands in an order the cache disagrees with. `body` must not call back
    /// into Store: the lock is not recursive.
    static func mutate(_ body: (inout Document) -> Void) {
        cache.withLock { slot in
            var doc = loaded(&slot)
            body(&doc)
            doc.savedAt = Date()
            slot = doc
            write(doc)
        }
    }

    /// Replaces the entire document. Used by import, which has already
    /// checked the incoming file; everything else should go through mutate.
    static func replace(with incoming: Document) {
        cache.withLock { slot in
            var doc = incoming
            doc.version = currentVersion
            doc.savedAt = Date()
            slot = doc
            write(doc)
        }
    }

    /// The cached document, reading it in on first use. Only ever called with
    /// the lock held, which is what `inout` on the cache slot stands for.
    private static func loaded(_ slot: inout Document?) -> Document {
        if let slot { return slot }
        migrateIfNeeded()
        let doc = read() ?? Document()
        slot = doc
        return doc
    }

    private static func read() -> Document? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(Document.self, from: data)
    }

    @discardableResult
    private static func write(_ doc: Document) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(doc) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: One-time consolidation

    /// Pulls records out of the two older layouts — the per-area JSON files,
    /// and before those the UserDefaults blobs — then clears both.
    private static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }

        // Already consolidated by hand, or a fresh install that wrote first.
        guard !FileManager.default.fileExists(atPath: url.path) else {
            discardOldStorage()
            return
        }

        var doc = Document()

        // Per-area files won, where they exist: that was the newer layout.
        if let pantry = legacyFile(PantryFile.self, named: "pantry.json") {
            doc.groceryItems = pantry.items
            doc.useLog = pantry.log
        } else {
            doc.groceryItems = legacyDefaults([GroceryItem].self, key: "groceryItems") ?? []
            doc.useLog = legacyDefaults([UseEntry].self, key: "groceryLog") ?? []
        }

        if let rota = legacyFile(TrashRota.self, named: "rota.json") {
            doc.trashRota = rota
        } else if let rota = legacyDefaults(TrashRota.self, key: "trashRota") {
            doc.trashRota = rota
        }

        if let ledger = legacyFile(LedgerFile.self, named: "ledger.json") {
            doc.stepLedger = ledger.batches
        } else {
            doc.stepLedger = legacyDefaults([WriteBatch].self, key: "writeBatches") ?? []
        }

        write(doc)
        discardOldStorage()
    }

    /// Old files were written with the iso8601 strategy, same as the new one.
    private static func legacyFile<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        let old = folder.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: old) else { return nil }
        return try? decoder().decode(T.self, from: data)
    }

    /// Old UserDefaults blobs were written with the default date strategy, so
    /// they need a plain decoder rather than the iso8601 one.
    private static func legacyDefaults<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func discardOldStorage() {
        for name in ["pantry.json", "rota.json", "ledger.json"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        let defaults = UserDefaults.standard
        for key in ["groceryItems", "groceryLog", "trashRota", "writeBatches", "storeMigratedV1"] {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Shapes of the superseded per-area files

private nonisolated struct PantryFile: Codable {
    var items: [GroceryItem] = []
    var log: [UseEntry] = []
}

private nonisolated struct LedgerFile: Codable {
    var batches: [WriteBatch] = []
}
