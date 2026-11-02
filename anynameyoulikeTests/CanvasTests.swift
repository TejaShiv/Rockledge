import Foundation
import Testing
@testable import anynameyoulike

/// Reading Canvas, and saying when things are due.
///
/// Nothing here touches the Keychain. The tests run inside the app's own
/// process and share its bundle, so a test that wrote a token would be
/// writing over the real one on the phone.
struct CanvasTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func at(_ year: Int, _ month: Int, _ day: Int,
                    _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    // MARK: Course names

    @Test func readsARealCourseName() throws {
        let parsed = try #require(CanvasCourseName.parse(
            "CS5610 17395 Web Development SEC 02 Fall 2026 [BOS-1-TR]", id: 7
        ))

        #expect(parsed.id == 7)
        #expect(parsed.code == "CS5610")
        #expect(parsed.title == "Web Development")
    }

    @Test func usesTheNameIKnowItBy() throws {
        // Whatever the registrar calls CS6620, it is Cloud Computing.
        let parsed = try #require(CanvasCourseName.parse(
            "CS6620 11223 Introduction To Cloud Comp SEC 01 Fall 2026 [BOS-1-MW]", id: 9
        ))

        #expect(parsed.title == "Cloud Computing")
    }

    @Test func keepsTheRegistrarsTitleForAClassItDoesNotKnow() throws {
        let parsed = try #require(CanvasCourseName.parse(
            "DS4400 20001 Machine Learning And Data Mining SEC 03 Spring 2027 [BOS-1-TF]",
            id: 11
        ))

        #expect(parsed.code == "DS4400")
        #expect(parsed.title == "Machine Learning And Data Mining")
    }

    @Test func acceptsACodeSplitAcrossTwoWords() throws {
        let parsed = try #require(CanvasCourseName.parse(
            "CS 5610 17395 Web Development SEC 02 Fall 2026 [BOS-1-TR]", id: 7
        ))

        #expect(parsed.code == "CS5610")
        #expect(parsed.title == "Web Development")
    }

    /// Canvas accounts are full of shells, sandboxes and orientation
    /// modules. None of them are classes.
    @Test func dropsAnythingThatIsNotACourse() {
        let notCourses = [
            "Student Orientation",
            "NU Sandbox",
            "CS5610",
            "CS5610 Web Development",                       // no SEC
            "Welcome 123 To Canvas SEC 01",                 // no course code
            "",
        ]

        for name in notCourses {
            #expect(CanvasCourseName.parse(name, id: 1) == nil, "accepted \(name)")
        }
    }

    @Test func refusesACourseWithNoTitleAtAll() {
        #expect(CanvasCourseName.parse("CS5610 17395 SEC 02 Fall 2026", id: 1) == nil)
    }

    // MARK: Which day a deadline belongs to

    /// The whole point: 2:59 AM here is 11:59 PM in California, which is the
    /// deadline that was actually set. Calling it Thursday hands you a day
    /// you do not have.
    @Test func theSmallHoursBelongToTheNightBefore() {
        let due = at(2026, 11, 12, 2, 59)        // Thursday, 2:59 AM

        #expect(CanvasDue.effectiveDay(for: due, calendar: calendar)
                == at(2026, 11, 11, 0))          // Wednesday
    }

    @Test func aDaytimeDeadlineKeepsItsOwnDay() {
        let due = at(2026, 11, 12, 14)

        #expect(CanvasDue.effectiveDay(for: due, calendar: calendar)
                == at(2026, 11, 12, 0))
    }

    @Test func sixInTheMorningIsAlreadyTheNewDay() {
        #expect(CanvasDue.effectiveDay(for: at(2026, 11, 12, 6), calendar: calendar)
                == at(2026, 11, 12, 0))
        #expect(CanvasDue.effectiveDay(for: at(2026, 11, 12, 5, 59), calendar: calendar)
                == at(2026, 11, 11, 0))
    }

    @Test func nightIsTheSmallHoursAndTheEvening() {
        #expect(CanvasDue.isNight(at(2026, 11, 12, 2), calendar: calendar))
        #expect(CanvasDue.isNight(at(2026, 11, 12, 22), calendar: calendar))
        #expect(CanvasDue.isNight(at(2026, 11, 12, 18), calendar: calendar))
        #expect(!CanvasDue.isNight(at(2026, 11, 12, 9), calendar: calendar))
        #expect(!CanvasDue.isNight(at(2026, 11, 12, 17, 59), calendar: calendar))
    }

    // MARK: How it reads

    @Test func saysTheDayTheWayYouWouldSayIt() {
        let now = at(2026, 11, 9, 12)            // Monday lunchtime

        func phrase(_ due: Date) -> String {
            CanvasDue.dayPhrase(for: due, from: now, calendar: calendar)
        }

        #expect(phrase(at(2026, 11, 9, 22)) == "Tonight")
        #expect(phrase(at(2026, 11, 9, 15)) == "Today")
        #expect(phrase(at(2026, 11, 10, 2, 59)) == "Tonight")     // rolls back
        #expect(phrase(at(2026, 11, 10, 22)) == "Tomorrow night")
        #expect(phrase(at(2026, 11, 10, 13)) == "Tomorrow")
        #expect(phrase(at(2026, 11, 11, 22)) == "Wednesday night")
        #expect(phrase(at(2026, 11, 12, 2, 59)) == "Wednesday night")
        #expect(phrase(at(2026, 11, 13, 13)) == "Friday")
        #expect(phrase(at(2026, 11, 16, 22)) == "Next Monday")
        #expect(phrase(at(2026, 11, 20, 13)) == "Next Friday")
        #expect(phrase(at(2026, 11, 8, 22)) == "Overdue")
    }

    /// Far enough out that the hour stops being the point.
    @Test func dropsTheNightOnceItIsAWeekAway() {
        let now = at(2026, 11, 9, 12)

        #expect(CanvasDue.dayPhrase(for: at(2026, 11, 16, 23, 59),
                                    from: now, calendar: calendar) == "Next Monday")
    }

    @Test func fallsBackToADateBeyondAFortnight() {
        let now = at(2026, 11, 9, 12)

        #expect(CanvasDue.dayPhrase(for: at(2026, 12, 15, 22),
                                    from: now, calendar: calendar) == "Dec 15")
    }

    @Test func saysTheTimeWithoutZeroMinutes() {
        #expect(CanvasDue.timePhrase(for: at(2026, 11, 11, 22), calendar: calendar)
                == "by 10 PM")
        #expect(CanvasDue.timePhrase(for: at(2026, 11, 12, 2, 59), calendar: calendar)
                == "by 2:59 AM")
        #expect(CanvasDue.timePhrase(for: at(2026, 11, 12, 9, 5), calendar: calendar)
                == "by 9:05 AM")
    }

    @Test func putsTheTwoTogether() {
        let now = at(2026, 11, 9, 12)

        #expect(CanvasDue.phrase(for: at(2026, 11, 11, 22), from: now, calendar: calendar)
                == "Wednesday night, by 10 PM")
    }

    // MARK: Paging

    @Test func followsTheNextLink() {
        let header = """
        <https://x.instructure.com/api/v1/courses?page=2&per_page=100>; rel="next",\
        <https://x.instructure.com/api/v1/courses?page=4&per_page=100>; rel="last"
        """

        #expect(CanvasAPI.nextPage(in: header)?.absoluteString
                == "https://x.instructure.com/api/v1/courses?page=2&per_page=100")
    }

    /// The last page says "prev" and "first" and nothing else, which is how
    /// paging terminates.
    @Test func stopsWhenThereIsNoNextLink() {
        let header = """
        <https://x.instructure.com/api/v1/courses?page=1>; rel="first",\
        <https://x.instructure.com/api/v1/courses?page=3>; rel="prev"
        """

        #expect(CanvasAPI.nextPage(in: header) == nil)
        #expect(CanvasAPI.nextPage(in: nil) == nil)
        #expect(CanvasAPI.nextPage(in: "") == nil)
    }

    // MARK: Snapshots

    private let web = CanvasClass(id: 1, code: "CS5610", title: "Web Development")
    private let cloud = CanvasClass(id: 2, code: "CS6620", title: "Cloud Computing")

    private func assignment(_ id: Int, _ course: Int, _ name: String,
                            _ due: Date, done: Bool = false) -> CanvasAssignment {
        CanvasAssignment(id: id, courseID: course, name: name,
                         dueAt: due, link: nil, isDone: done)
    }

    private var term: CanvasSnapshot {
        CanvasSnapshot(
            classes: [web, cloud],
            assignments: [
                assignment(10, 1, "Q3 JavaScript", at(2026, 11, 11, 22)),
                assignment(11, 1, "Q2 CSS", at(2026, 11, 9, 22), done: true),
                assignment(12, 2, "Lab 4", at(2026, 11, 13, 23, 59)),
                assignment(13, 1, "Final project", at(2026, 12, 10, 22)),
            ],
            fetchedAt: at(2026, 11, 9, 12)
        )
    }

    @Test func handedInWorkDropsOutOfTheList() {
        let outstanding = term.outstanding

        #expect(outstanding.map(\.id) == [10, 12, 13])
    }

    @Test func theNextThingIsTheSoonestUnsubmittedOne() {
        #expect(term.next?.name == "Q3 JavaScript")
    }

    @Test func countsOnlyTheComingWeek() {
        // Final project is a month out; Q2 is handed in.
        #expect(term.dueThisWeek(from: at(2026, 11, 9, 12), calendar: calendar) == 2)
    }

    @Test func theFortnightWindowLeavesOutTheFarFuture() {
        let soon = term.soon(within: 14, from: at(2026, 11, 9, 12), calendar: calendar)

        #expect(soon.map(\.id) == [10, 12])
    }

    // MARK: Reminders

    @Test func twoNudgesPerPieceOfWork() {
        let now = at(2026, 11, 2, 12)
        let plan = CanvasReminders.plan(for: term, now: now, calendar: calendar)

        let forQ3 = plan.filter { $0.identifier.hasPrefix("canvas-10-") }

        #expect(forQ3.count == 2)
        #expect(Set(forQ3.map(\.identifier)) == ["canvas-10-2d", "canvas-10-1d"])
    }

    /// Both lines read as they will on the morning they arrive, not as they
    /// read today.
    @Test func saysTheRightDayOnTheDayItArrives() throws {
        let now = at(2026, 11, 2, 12)
        let plan = CanvasReminders.plan(for: term, now: now, calendar: calendar)

        // Q3 JavaScript is due Wednesday 11 Nov at 10 PM.
        let twoDays = try #require(plan.first { $0.identifier == "canvas-10-2d" })
        let oneDay = try #require(plan.first { $0.identifier == "canvas-10-1d" })

        #expect(twoDays.fire == at(2026, 11, 9, 9))
        #expect(twoDays.title == "Coming up Wednesday night")
        #expect(twoDays.body == "Q3 JavaScript, Web Development, by 10 PM")

        #expect(oneDay.fire == at(2026, 11, 10, 9))
        #expect(oneDay.title == "Due tomorrow night")
        #expect(oneDay.body == "Q3 JavaScript, Web Development, by 10 PM")
    }

    /// A deadline in the small hours is reminded about against the evening
    /// it really belongs to.
    @Test func remindsAgainstTheNightBeforeNotTheCalendarDay() throws {
        let due = at(2026, 11, 12, 2, 59)       // Thursday 2:59 AM
        let snapshot = CanvasSnapshot(
            classes: [web],
            assignments: [assignment(20, 1, "Q4 React", due)],
            fetchedAt: nil
        )

        let plan = CanvasReminders.plan(
            for: snapshot, now: at(2026, 11, 2, 12), calendar: calendar
        )

        let twoDays = try #require(plan.first { $0.identifier == "canvas-20-2d" })

        // Wednesday is the real due day, so two days out is Monday.
        #expect(twoDays.fire == at(2026, 11, 9, 9))
        #expect(twoDays.title == "Coming up Wednesday night")
        #expect(twoDays.body == "Q4 React, Web Development, by 2:59 AM")
    }

    @Test func neverSchedulesAReminderInThePast() {
        // Tuesday lunchtime: the two-day nudge for Wednesday's work was
        // Monday morning and is long gone.
        let plan = CanvasReminders.plan(
            for: term, now: at(2026, 11, 10, 12), calendar: calendar
        )

        #expect(plan.allSatisfy { $0.fire > at(2026, 11, 10, 12) })
        #expect(!plan.contains { $0.identifier == "canvas-10-2d" })
        #expect(!plan.contains { $0.identifier == "canvas-10-1d" })
    }

    @Test func doesNotNagAboutWorkAlreadyHandedIn() {
        let plan = CanvasReminders.plan(
            for: term, now: at(2026, 11, 1, 12), calendar: calendar
        )

        #expect(!plan.contains { $0.identifier.hasPrefix("canvas-11-") })
    }

    @Test func ignoresAnAssignmentWhoseClassIsMissing() {
        let orphan = CanvasSnapshot(
            classes: [],
            assignments: [assignment(30, 99, "Ghost", at(2026, 11, 20, 22))],
            fetchedAt: nil
        )

        #expect(CanvasReminders.plan(
            for: orphan, now: at(2026, 11, 1, 12), calendar: calendar
        ).isEmpty)
    }

    @Test func comesOutSoonestFirst() {
        let plan = CanvasReminders.plan(
            for: term, now: at(2026, 11, 1, 12), calendar: calendar
        )

        #expect(plan == plan.sorted { $0.fire < $1.fire })
    }

    /// iOS keeps 64 pending notifications and drops the rest silently, so
    /// the nightly reminder, the trash rota and the signing warnings all
    /// need room left over.
    @Test func staysInsideTheNotificationBudget() {
        let many = (0..<60).map {
            assignment(100 + $0, 1, "Task \($0)",
                       at(2026, 11, 20, 22).addingTimeInterval(Double($0) * 86_400))
        }
        let heavy = CanvasSnapshot(classes: [web], assignments: many, fetchedAt: nil)

        let plan = CanvasReminders.plan(
            for: heavy, now: at(2026, 11, 1, 12), calendar: calendar
        )

        #expect(plan.count == CanvasReminders.budget)
        #expect(plan.count < 50)
    }

    /// Dropping the overflow has to drop the furthest away, never the
    /// soonest.
    @Test func keepsTheSoonestWhenItRunsOutOfRoom() {
        let many = (0..<60).map {
            assignment(100 + $0, 1, "Task \($0)",
                       at(2026, 11, 20, 22).addingTimeInterval(Double($0) * 86_400))
        }
        let heavy = CanvasSnapshot(classes: [web], assignments: many, fetchedAt: nil)

        let plan = CanvasReminders.plan(
            for: heavy, now: at(2026, 11, 1, 12), calendar: calendar
        )

        #expect(plan.first?.identifier == "canvas-100-2d")
        #expect(plan.allSatisfy { !$0.identifier.hasPrefix("canvas-159-") })
    }

    /// Identifiers carry the assignment id, so a rescheduled deadline
    /// replaces its old reminder rather than adding a second one.
    @Test func identifiersAreStableAcrossRuns() {
        let first = CanvasReminders.plan(for: term, now: at(2026, 11, 1, 12),
                                         calendar: calendar).map(\.identifier)
        let again = CanvasReminders.plan(for: term, now: at(2026, 11, 1, 12),
                                         calendar: calendar).map(\.identifier)

        #expect(first == again)
        #expect(Set(first).count == first.count)
        #expect(first.allSatisfy { $0.hasPrefix(CanvasReminders.prefix) })
    }

    // MARK: Colours

    @Test func aClassAlwaysGetsTheSameColour() {
        #expect(CanvasPalette.tint(for: "CS5610") == CanvasPalette.web)
        #expect(CanvasPalette.tint(for: "CS6620") == CanvasPalette.cloud)
        // Stable across calls, which hashValue would not be across launches.
        #expect(CanvasPalette.tint(for: "DS4400") == CanvasPalette.tint(for: "DS4400"))
        #expect(CanvasPalette.tint(for: "DS4400") != CanvasPalette.tint(for: "CS5610"))
    }
}

/// The reply, and the ways it can arrive wrong.
///
/// "Canvas error 200" was a real bug: an Accept header asked for string ids,
/// every decode failed, and the only thing reported back was the HTTP status,
/// which was fine. These cover the shapes and the message.
struct CanvasReplyTests {

    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: CanvasAPI.readable(Data(json.utf8)))
    }

    /// Canvas can spoil a cross-site read by prefixing this. It is not JSON.
    @Test func stripsTheAntiHijackingPrefix() throws {
        let guarded = #"while(1);[{"id":1,"name":"x"}]"#
        let plain = #"[{"id":1,"name":"x"}]"#

        #expect(CanvasAPI.readable(Data(guarded.utf8)) == Data(plain.utf8))
        // Anything without the prefix is handed back untouched.
        #expect(CanvasAPI.readable(Data(plain.utf8)) == Data(plain.utf8))
        #expect(CanvasAPI.readable(Data()) == Data())
    }

    @Test func readsAnAssignmentWithNumericIDs() throws {
        let json = """
        [{"id": 991, "name": "Q3 JavaScript", "due_at": "2026-11-12T02:59:00Z",
          "html_url": "https://northeastern.instructure.com/courses/1/assignments/991",
          "submission": {"submitted_at": null, "workflow_state": "unsubmitted"}}]
        """

        let parsed = try decode(json, as: [CanvasWireProbe].self)

        #expect(parsed[0].id == 991)
        #expect(parsed[0].name == "Q3 JavaScript")
    }

    /// The exact failure that produced "Canvas error 200".
    @Test func readsAnAssignmentWhoseIDsCameBackQuoted() throws {
        let json = #"[{"id": "991", "name": "Q3 JavaScript"}]"#

        let parsed = try decode(json, as: [CanvasWireProbe].self)

        #expect(parsed[0].id == 991)
    }

    @Test func anUnreadableReplySaysWhatWasWrongNotTheStatusCode() {
        let failure = CanvasAPI.Failure.unreadable("the reply is not a Int")

        #expect(failure.message == "Canvas replied oddly: the reply is not a Int")
        #expect(!failure.needsNewToken)
        // The point of the change: no status code in the message.
        #expect(!failure.message.contains("200"))
    }

    @Test func onlyAToken401SaysTheTokenNeedsReplacing() {
        #expect(CanvasAPI.Failure.unauthorised.needsNewToken)
        #expect(!CanvasAPI.Failure.offline.needsNewToken)
        #expect(!CanvasAPI.Failure.badResponse(500).needsNewToken)
        #expect(!CanvasAPI.Failure.noToken.needsNewToken)
    }
}

/// Stands in for the private wire type so the id handling can be exercised
/// without opening it up.
struct CanvasWireProbe: Decodable {
    var id: Int
    var name: String?

    enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try CanvasAPI.identifier(box, .id)
        name = try box.decodeIfPresent(String.self, forKey: .name)
    }
}

/// Telling this term's classes from the ones already sat through.
///
/// `enrollment_state=active` describes the enrolment, not the term, so a
/// first-semester course turned up in the third. Two signals settle it:
/// Canvas's own term end date, and the term printed in the course name.
struct CanvasTermTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func at(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Reading a term

    @Test func readsATermLabel() throws {
        let fall = try #require(CanvasTerm(label: "Fall 2026"))

        #expect(fall.season == .fall)
        #expect(fall.year == 2026)
        #expect(fall.label == "Fall 2026")
    }

    @Test func refusesSomethingThatIsNotATerm() {
        #expect(CanvasTerm(label: "Fall") == nil)
        #expect(CanvasTerm(label: "Autumn 2026") == nil)
        #expect(CanvasTerm(label: "Fall twenty") == nil)
        #expect(CanvasTerm(label: "") == nil)
    }

    @Test func termsSortInTheOrderTheyHappen() {
        #expect(CanvasTerm(season: .spring, year: 2026)
                < CanvasTerm(season: .fall, year: 2026))
        #expect(CanvasTerm(season: .fall, year: 2025)
                < CanvasTerm(season: .spring, year: 2026))
        #expect(CanvasTerm(season: .summer, year: 2026)
                < CanvasTerm(season: .fall, year: 2026))
    }

    @Test func worksOutWhichTermItIsNow() {
        #expect(CanvasTerm.current(on: at(2026, 11, 2), calendar: calendar)
                == CanvasTerm(season: .fall, year: 2026))
        #expect(CanvasTerm.current(on: at(2026, 2, 10), calendar: calendar)
                == CanvasTerm(season: .spring, year: 2026))
        #expect(CanvasTerm.current(on: at(2026, 6, 1), calendar: calendar)
                == CanvasTerm(season: .summer, year: 2026))
    }

    @Test func picksTheTermOutOfACourseName() throws {
        let parsed = try #require(CanvasCourseName.parse(
            "CS5610 17395 Web Development SEC 02 Fall 2026 [BOS-1-TR]", id: 7
        ))

        #expect(parsed.term == "Fall 2026")
    }

    /// The title must not swallow the term, and the term must not come from
    /// a word that happens to sit in the title.
    @Test func doesNotConfuseTheTitleWithTheTerm() throws {
        let parsed = try #require(CanvasCourseName.parse(
            "CS3200 14001 Fall Detection Systems SEC 01 Spring 2027 [BOS-1-MW]", id: 3
        ))

        #expect(parsed.title == "Fall Detection Systems")
        #expect(parsed.term == "Spring 2027")
    }

    @Test func copesWithACourseNameWithNoTermInIt() throws {
        let parsed = try #require(CanvasCourseName.parse(
            "CS5610 17395 Web Development SEC 02", id: 7
        ))

        #expect(parsed.term == nil)
    }

    // MARK: Hiding what is over

    private let november = Date(timeIntervalSince1970: 1_793_000_000)   // Nov 2026

    /// The case that went wrong: Fundamentals of Computer Networking from
    /// first semester, still enrolled, showing up in the third.
    @Test func lastYearsClassIsOver() {
        #expect(CanvasAPI.isOver(termLabel: "Fall 2025", termEndsAt: nil,
                                 now: at(2026, 11, 2), calendar: calendar))
        #expect(CanvasAPI.isOver(termLabel: "Spring 2026", termEndsAt: nil,
                                 now: at(2026, 11, 2), calendar: calendar))
    }

    @Test func thisTermsClassStays() {
        #expect(!CanvasAPI.isOver(termLabel: "Fall 2026", termEndsAt: nil,
                                  now: at(2026, 11, 2), calendar: calendar))
    }

    /// Registering early must not hide the class.
    @Test func nextTermsClassStays() {
        #expect(!CanvasAPI.isOver(termLabel: "Spring 2027", termEndsAt: nil,
                                  now: at(2026, 11, 2), calendar: calendar))
    }

    /// Canvas's own date wins when it has one.
    @Test func canvasSayingTheTermEndedIsEnough() {
        #expect(CanvasAPI.isOver(termLabel: nil, termEndsAt: at(2026, 5, 1),
                                 now: at(2026, 11, 2), calendar: calendar))
        #expect(!CanvasAPI.isOver(termLabel: nil, termEndsAt: at(2026, 12, 20),
                                  now: at(2026, 11, 2), calendar: calendar))
    }

    /// Showing one stale class is a smaller failure than hiding real work,
    /// so anything it cannot place stays on screen.
    @Test func keepsAClassItCannotPlace() {
        #expect(!CanvasAPI.isOver(termLabel: nil, termEndsAt: nil,
                                  now: at(2026, 11, 2), calendar: calendar))
        #expect(!CanvasAPI.isOver(termLabel: "Michaelmas 2026", termEndsAt: nil,
                                  now: at(2026, 11, 2), calendar: calendar))
    }
}
