//
//  Store.swift
//  anynameyoulike
//
//  Created by Tejas Shivaprasad on 10/4/26.
//


import Foundation

/// Every durable record lives as a JSON file in Documents, so it is visible
/// in the Files app, editable by hand, and included in device backups.
enum Store {
    static let pantryFile = "pantry.json"
    static let rotaFile = "rota.json"
    static let ledgerFile = "ledger.json"

    private static let migratedKey = "storeMigratedV1"
    private static var checked = false

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func url(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    // MARK: Read and write

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        migrateIfNeeded()
        guard let data = try? Data(contentsOf: url(name)) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    @discardableResult
    static func save<T: Encodable>(_ value: T, to name: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(value) else { return false }
        do {
            try data.write(to: url(name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: One-time move out of UserDefaults

    /// Old data was written with the default date strategy, so it needs a
    /// plain decoder rather than the iso8601 one used for the files.
    private static func legacy<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func migrateIfNeeded() {
        guard !checked else { return }
        checked = true

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }

        var pantry = PantryFile()
        if let items = legacy([GroceryItem].self, key: "groceryItems") {
            pantry.items = items
        }
        if let log = legacy([UseEntry].self, key: "groceryLog") {
            pantry.log = log
        }
        if !pantry.items.isEmpty || !pantry.log.isEmpty {
            save(pantry, to: pantryFile)
        }

        if let rota = legacy(TrashRota.self, key: "trashRota") {
            save(rota, to: rotaFile)
        }

        if let batches = legacy([WriteBatch].self, key: "writeBatches") {
            save(LedgerFile(batches: batches), to: ledgerFile)
        }

        defaults.removeObject(forKey: "groceryItems")
        defaults.removeObject(forKey: "groceryLog")
        defaults.removeObject(forKey: "trashRota")
        defaults.removeObject(forKey: "writeBatches")
        defaults.set(true, forKey: migratedKey)
    }
}

// MARK: - File shapes

struct PantryFile: Codable {
    var version = 1
    var items: [GroceryItem] = []
    var log: [UseEntry] = []
}

struct LedgerFile: Codable {
    var version = 1
    var batches: [WriteBatch] = []
}