import Foundation
import Testing
@testable import anynameyoulike

/// Store is shared mutable state reached from views, from the grocery and
/// trash models, and from an App Intent that does not run on the main actor.
/// These tests are about the lock holding under contention.
///
/// Serialised against each other: there is one Store, so siblings running at
/// the same time would be changing the very totals these tests assert on. The
/// contention under test is the task groups inside each one.
@Suite(.serialized)
struct StoreTests {

    private func item(_ name: String) -> GroceryItem {
        GroceryItem(
            name: name, measure: .count, unit: "units",
            packSize: 1, remaining: 1, startRate: 1
        )
    }

    /// Removes anything this test added, so a failure does not poison the
    /// document for later runs.
    private func discard(taggedWith tag: String) {
        Store.mutate { doc in
            doc.groceryItems.removeAll { $0.name.hasPrefix(tag) }
        }
    }

    @Test func concurrentMutationsDoNotLoseWrites() async {
        let runs = 200
        let tag = "concurrency-\(UUID().uuidString)"
        defer { discard(taggedWith: tag) }

        let before = Store.document.groceryItems.count

        // Every task appends to the same array. A read-modify-write that was
        // only atomic step by step would drop most of these.
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<runs {
                group.addTask {
                    Store.mutate { $0.groceryItems.append(item("\(tag)-\(index)")) }
                }
            }
        }

        let items = Store.document.groceryItems
        let mine = items.filter { $0.name.hasPrefix(tag) }

        #expect(mine.count == runs)
        #expect(Set(mine.map(\.name)).count == runs)   // no duplicates either
        #expect(items.count == before + runs)
    }

    /// The file is written under the same lock, so whatever landed on disk
    /// last has to be the whole document, not a half-applied one.
    @Test func theFileEndsUpAgreeingWithTheCache() async throws {
        let runs = 60
        let tag = "file-\(UUID().uuidString)"
        defer { discard(taggedWith: tag) }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<runs {
                group.addTask {
                    Store.mutate { $0.groceryItems.append(item("\(tag)-\(index)")) }
                }
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: Store.url)
        let onDisk = try decoder.decode(Store.Document.self, from: data)

        #expect(onDisk.groceryItems.filter { $0.name.hasPrefix(tag) }.count == runs)
        #expect(onDisk.groceryItems.count == Store.document.groceryItems.count)
    }

    /// Readers running against a storm of writers must never see a torn
    /// document — every read is a whole one somebody wrote.
    @Test func concurrentReadsSeeWholeDocuments() async {
        let runs = 100
        let tag = "reads-\(UUID().uuidString)"
        defer { discard(taggedWith: tag) }

        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<runs {
                group.addTask {
                    Store.mutate { $0.groceryItems.append(item("\(tag)-\(index)")) }
                    return true
                }
                group.addTask {
                    // Counts only ever grow here, and names are never blank.
                    let doc = Store.document
                    return doc.groceryItems.allSatisfy { !$0.name.isEmpty }
                }
            }

            for await intact in group {
                #expect(intact)
            }
        }

        #expect(Store.document.groceryItems.filter { $0.name.hasPrefix(tag) }.count == runs)
    }

    /// Writes through different areas of the document must not clobber each
    /// other: the whole read-modify-write is one critical section.
    @Test func mutationsToDifferentAreasAllSurvive() async {
        let runs = 50
        let tag = "areas-\(UUID().uuidString)"
        let people = Store.document.trashRota.people
        defer {
            discard(taggedWith: tag)
            Store.mutate { $0.trashRota.people = people }
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<runs {
                group.addTask {
                    Store.mutate { $0.groceryItems.append(item("\(tag)-\(index)")) }
                }
                group.addTask {
                    Store.mutate { $0.trashRota.people.append("\(tag)-\(index)") }
                }
            }
        }

        let doc = Store.document
        #expect(doc.groceryItems.filter { $0.name.hasPrefix(tag) }.count == runs)
        #expect(doc.trashRota.people.filter { $0.hasPrefix(tag) }.count == runs)
    }
}
