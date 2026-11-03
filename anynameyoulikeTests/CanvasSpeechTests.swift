import Foundation
import Testing
@testable import anynameyoulike

/// What Siri says when asked what is due.
///
/// Built from the cached snapshot, so these run without a token, a network
/// or the engine.
struct CanvasSpeechTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: y, month: m, day: d, hour: h, minute: min
        ))!
    }

    private let web = CanvasClass(id: 1, code: "CS5610", title: "Web Development")
    private let cloud = CanvasClass(id: 2, code: "CS6620", title: "Cloud Computing")

    private func work(_ id: Int, _ course: Int, _ name: String,
                      _ due: Date, done: Bool = false) -> CanvasAssignment {
        CanvasAssignment(id: id, courseID: course, name: name,
                         dueAt: due, link: nil, isDone: done)
    }

    private func say(_ snapshot: CanvasSnapshot,
                     connected: Bool = true,
                     now: Date? = nil) -> String {
        CanvasSpeech.summary(
            for: snapshot,
            connected: connected,
            now: now ?? at(2026, 11, 9, 12),
            calendar: calendar
        )
    }

    // MARK: Nothing to say

    @Test func saysSoWhenCanvasIsNotConnected() {
        let spoken = say(CanvasSnapshot(), connected: false)

        #expect(spoken.contains("isn't connected"))
        #expect(spoken.contains("token"))
    }

    /// Connected but nothing cached yet is a different problem from no
    /// token, and saying "not connected" would send you to the wrong place.
    @Test func saysSomethingElseWhenConnectedButEmpty() {
        let spoken = say(CanvasSnapshot(), connected: true)

        #expect(!spoken.contains("isn't connected"))
        #expect(spoken.contains("classes"))
    }

    // MARK: One line per class

    @Test func namesEachClassAndItsNextPieceOfWork() {
        let spoken = say(CanvasSnapshot(
            classes: [web, cloud],
            assignments: [
                work(10, 1, "Q3 JavaScript", at(2026, 11, 11, 22)),
                work(11, 2, "Lab 4", at(2026, 11, 13, 23, 59)),
            ],
            fetchedAt: nil
        ))

        #expect(spoken == "For Web Development, Q3 JavaScript, due Wednesday night. "
                        + "For Cloud Computing, Lab 4, due Friday night.")
    }

    @Test func saysAClassWithNothingLeftIsClear() {
        let spoken = say(CanvasSnapshot(
            classes: [web, cloud],
            assignments: [work(10, 1, "Q3 JavaScript", at(2026, 11, 11, 22))],
            fetchedAt: nil
        ))

        #expect(spoken.contains("Cloud Computing is clear."))
    }

    @Test func everyClassGetsItsOwnSentence() {
        let spoken = say(CanvasSnapshot(
            classes: [web, cloud], assignments: [], fetchedAt: nil
        ))

        // Two full stops, so Siri pauses between them rather than running
        // the classes together.
        #expect(spoken == "Web Development is clear. Cloud Computing is clear.")
    }

    // MARK: Which piece of work

    @Test func picksTheSoonestUnsubmittedOne() {
        let spoken = say(CanvasSnapshot(
            classes: [web],
            assignments: [
                work(12, 1, "Final project", at(2026, 12, 10, 22)),
                work(10, 1, "Q3 JavaScript", at(2026, 11, 11, 22)),
            ],
            fetchedAt: nil
        ))

        #expect(spoken.contains("Q3 JavaScript"))
        #expect(!spoken.contains("Final project"))
    }

    @Test func ignoresWorkAlreadyHandedIn() {
        let spoken = say(CanvasSnapshot(
            classes: [web],
            assignments: [work(10, 1, "Q3 JavaScript",
                               at(2026, 11, 11, 22), done: true)],
            fetchedAt: nil
        ))

        #expect(spoken == "Web Development is clear.")
    }

    // MARK: Saying the time

    /// The due-date rule is reused, not reimplemented: a deadline in the
    /// small hours belongs to the night before out loud too.
    @Test func speaksTheSameDayRuleTheScreensUse() {
        let spoken = say(CanvasSnapshot(
            classes: [web],
            assignments: [work(10, 1, "Q4 React", at(2026, 11, 12, 2, 59))],
            fetchedAt: nil
        ))

        #expect(spoken.contains("due Wednesday night"))
    }

    @Test func lowercasesTheDayPhraseAfterDue() {
        let spoken = say(CanvasSnapshot(
            classes: [web],
            assignments: [work(10, 1, "Q3", at(2026, 11, 9, 22))],
            fetchedAt: nil
        ))

        #expect(spoken.contains("due tonight"))
        #expect(!spoken.contains("due Tonight"))
    }

    /// "Due overdue" is not a sentence.
    @Test func doesNotSayDueOverdue() {
        let spoken = say(CanvasSnapshot(
            classes: [web],
            assignments: [work(10, 1, "Q1", at(2026, 11, 5, 22))],
            fetchedAt: nil
        ))

        #expect(spoken.contains("which is overdue"))
        #expect(!spoken.lowercased().contains("due overdue"))
    }
}

/// Capitalisation in the spoken line.
///
/// It is read aloud, but it is also shown as a dialog, and "due wednesday
/// night" reads as a mistake on screen.
struct CanvasSpeechCaseTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func line(due: Date) -> String {
        CanvasSpeech.summary(
            for: CanvasSnapshot(
                classes: [CanvasClass(id: 1, code: "CS5610", title: "Web Development")],
                assignments: [CanvasAssignment(id: 1, courseID: 1, name: "Q",
                                               dueAt: due, link: nil, isDone: false)],
                fetchedAt: nil
            ),
            connected: true,
            now: at(2026, 11, 9, 12),
            calendar: calendar
        )
    }

    @Test func lowersTheRelativeWords() {
        #expect(line(due: at(2026, 11, 9, 22)).contains("due tonight"))
        #expect(line(due: at(2026, 11, 9, 15)).contains("due today"))
        #expect(line(due: at(2026, 11, 10, 22)).contains("due tomorrow night"))
        #expect(line(due: at(2026, 11, 16, 22)).contains("due next Monday"))
    }

    /// Weekdays and months are proper nouns and stay as they are.
    @Test func leavesProperNounsAlone() {
        #expect(line(due: at(2026, 11, 11, 22)).contains("due Wednesday night"))
        #expect(line(due: at(2026, 11, 13, 13)).contains("due Friday"))
        #expect(line(due: at(2026, 12, 15, 22)).contains("due Dec 15"))
    }

    /// "Next Monday" keeps the weekday but loses the leading capital.
    @Test func lowersNextButNotTheDayAfterIt() {
        let spoken = line(due: at(2026, 11, 16, 22))

        #expect(spoken.contains("next Monday"))
        #expect(!spoken.contains("Next Monday"))
        #expect(!spoken.contains("next monday"))
    }
}
