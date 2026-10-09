import Foundation
import Testing
@testable import anynameyoulike

/// Import validation. Getting this wrong destroys the only copy of the data,
/// so the refusals matter more than the acceptances.
struct BackupTests {

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private var realistic: String {
        """
        {
          "version": 1,
          "savedAt": "2026-10-05T05:55:07Z",
          "groceryItems": [{
            "id": "81DB66BF-9040-434F-B31F-176DF9959B3F",
            "measure": "count", "name": "Eggs", "openedAt": "2026-10-04T22:22:43Z",
            "packSize": 12, "remaining": 9, "startRate": 2, "tare": 0, "unit": "units"
          }],
          "useLog": [],
          "trashRota": {
            "anchorIndex": 0, "anchorMonday": "2026-09-28T04:00:00Z",
            "me": 2, "people": ["Dheeraj", "Agilan", "Me"]
          },
          "stepLedger": [],
          "transit": {}, "transitHome": {}
        }
        """
    }

    // MARK: What it accepts

    @Test func readsADocumentItWrote() throws {
        let document = try Backup.inspect(json(realistic))

        #expect(document.groceryItems.count == 1)
        #expect(document.groceryItems.first?.name == "Eggs")
        #expect(document.trashRota.people == ["Dheeraj", "Agilan", "Me"])
        #expect(document.trashRota.me == 2)
    }

    @Test func acceptsAnOlderDocument() throws {
        let older = realistic.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 0")

        #expect(throws: Never.self) { try Backup.inspect(json(older)) }
    }

    @Test func roundTripsThroughTheExportedFile() throws {
        let url = try Backup.exportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let written = try Data(contentsOf: url)
        let back = try Backup.inspect(written)

        #expect(back.version == Store.currentVersion)
        #expect(url.lastPathComponent.hasPrefix("kalla-"))
        #expect(url.pathExtension == "json")
    }

    // MARK: What it refuses

    /// The decoder is deliberately forgiving, so any JSON object at all
    /// decodes to an empty document. Without the version check an import of
    /// the wrong file would wipe everything and report success.
    @Test func refusesJSONThatIsNotADocument() {
        #expect(throws: Backup.Fault.notADocument) {
            try Backup.inspect(json(#"{"hello": "world"}"#))
        }
        #expect(throws: Backup.Fault.notADocument) {
            try Backup.inspect(json("{}"))
        }
    }

    @Test func refusesSomethingThatIsNotJSONAtAll() {
        #expect(throws: Backup.Fault.notADocument) {
            try Backup.inspect(json("not json, just words"))
        }
        #expect(throws: Backup.Fault.notADocument) {
            try Backup.inspect(Data())
        }
    }

    @Test func refusesAListRatherThanADocument() {
        #expect(throws: Backup.Fault.notADocument) {
            try Backup.inspect(json("[{\"version\": 1}]"))
        }
    }

    @Test func refusesADocumentFromANewerBuild() {
        let newer = realistic.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 99")

        #expect(throws: Backup.Fault.tooNew(found: 99, understood: Store.currentVersion)) {
            try Backup.inspect(json(newer))
        }
    }

    @Test func refusalsSayWhatToDo() {
        let tooNew = Backup.Fault.tooNew(found: 99, understood: 1)
        #expect(tooNew.errorDescription?.contains("99") == true)
        #expect(tooNew.errorDescription?.contains("Update the app") == true)
        #expect(Backup.Fault.notADocument.errorDescription?.contains("version number") == true)
    }

    @Test func refusesAVersionThatIsNotANumber() {
        let odd = realistic.replacingOccurrences(of: "\"version\": 1", with: "\"version\": \"one\"")

        #expect(throws: Backup.Fault.notADocument) { try Backup.inspect(json(odd)) }
    }

    @Test func refusesAMissingFile() {
        let nowhere = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID()).json")

        #expect(throws: Backup.Fault.unreadable) { try Backup.inspect(nowhere) }
    }

    // MARK: What it straightens out

    /// A hand-edited file is a supported way to use this document, so it will
    /// not always be internally consistent.
    @Test func putsSomebodyBackInAnEmptyRota() {
        var document = Store.Document()
        document.trashRota.people = []

        let fixed = Backup.repaired(document)

        #expect(fixed.trashRota.people == ["Me"])
        #expect(fixed.trashRota.me == 0)
    }

    @Test func pullsAnOutOfRangeMeBackIntoTheList() {
        var document = Store.Document()
        document.trashRota.people = ["A", "B"]
        document.trashRota.me = 7

        #expect(Backup.repaired(document).trashRota.me == 0)
    }

    @Test func dropsQuantitiesThatAreNotRealNumbers() {
        var document = Store.Document()
        document.groceryItems = [
            GroceryItem(name: "fine", measure: .count, unit: "u",
                        packSize: 10, remaining: 4, startRate: 1),
            GroceryItem(name: "broken", measure: .count, unit: "u",
                        packSize: .nan, remaining: 4, startRate: 1),
            GroceryItem(name: "endless", measure: .count, unit: "u",
                        packSize: 10, remaining: .infinity, startRate: 1),
        ]

        let fixed = Backup.repaired(document)

        #expect(fixed.groceryItems.map(\.name) == ["fine"])
    }

    @Test func leavesAHealthyDocumentAlone() throws {
        let document = try Backup.inspect(json(realistic))

        let fixed = Backup.repaired(document)

        #expect(fixed.groceryItems.map(\.name) == document.groceryItems.map(\.name))
        #expect(fixed.trashRota.people == document.trashRota.people)
        #expect(fixed.trashRota.me == 2)
        #expect(fixed.useLog.count == document.useLog.count)
    }

    // MARK: Summary shown in the confirmation

    @Test func summarisesWhatIsAboutToBeReplaced() throws {
        let summary = Backup.Summary(try Backup.inspect(json(realistic)))

        #expect(summary.groceryItems == 1)
        #expect(summary.people == 3)
        #expect(summary.lines.contains("1 grocery item"))
        #expect(summary.lines.contains("3 in the trash rota"))
    }

    @Test func countsReadNaturallyWhenPlural() {
        var document = Store.Document()
        document.groceryItems = (0..<3).map {
            GroceryItem(name: "i\($0)", measure: .count, unit: "u",
                        packSize: 1, remaining: 1, startRate: 1)
        }

        #expect(Backup.Summary(document).lines.contains("3 grocery items"))
    }

    // MARK: Rolling local snapshots

    /// Exercised against a scratch folder, so a test never prunes the real
    /// snapshots or writes one into Documents.
    @Test func keepsOnlyTheMostRecentSeven() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Ten files, each a day older than the last.
        for day in 0..<10 {
            let url = scratch.appendingPathComponent("kalla-\(day).json")
            try Data("{}".utf8).write(to: url)
            let when = Date().addingTimeInterval(Double(-day) * 86_400)
            try FileManager.default.setAttributes([.modificationDate: when],
                                                  ofItemAtPath: url.path)
        }

        let all = (try FileManager.default.contentsOfDirectory(at: scratch,
                                                               includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "json" }
            .sorted { Backup.Snapshots.takenAt($0) > Backup.Snapshots.takenAt($1) }

        #expect(all.count == 10)
        #expect(all.first?.lastPathComponent == "kalla-0.json")   // newest first
        #expect(all.last?.lastPathComponent == "kalla-9.json")

        for old in all.dropFirst(Backup.Snapshots.keep) {
            try FileManager.default.removeItem(at: old)
        }

        let left = (try FileManager.default.contentsOfDirectory(at: scratch,
                                                                includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "json" }
        #expect(left.count == Backup.Snapshots.keep)
        #expect(left.contains { $0.lastPathComponent == "kalla-0.json" })
        #expect(!left.contains { $0.lastPathComponent == "kalla-9.json" })
    }

    @Test func keepsSeven() {
        #expect(Backup.Snapshots.keep == 7)
    }

    /// A snapshot is a copy of the live document, so it has to come back
    /// through the same validation as any other file.
    @Test func aSnapshotReadsBackLikeAnyOtherBackup() throws {
        let url = try Backup.exportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try Backup.inspect(url)
        #expect(document.version == Store.currentVersion)
    }

    @Test func writesNothingWhenTodaysCopyAlreadyExists() {
        // The real folder, but only ever reading: with a snapshot from the
        // last day present this must be a no-op rather than piling up copies.
        let before = Backup.Snapshots.all().count
        if let newest = Backup.Snapshots.all().first,
           Date().timeIntervalSince(Backup.Snapshots.takenAt(newest)) < 86_400 {
            #expect(Backup.Snapshots.writeIfDue() == nil)
            #expect(Backup.Snapshots.all().count == before)
        }
    }
}
