import Foundation
@testable import pmstt
import Testing

@Suite("School day Live Activity projection")
struct SchoolDayActivityProjectorTests {
	private let calendar: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Australia/Perth")!
		return calendar
	}()

	@Test("Every school transition maps to the intended phase")
	func transitionPhases() throws {
		let projector = SchoolDayActivityProjector(calendar: calendar)
		let base = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 8)))
		let subjects = [subject(name: "Maths", period: 1)]
		let expected: [SchoolDayTransition: SchoolDayActivityPhase] = [
			.morning: .beforeSchool,
			.period1: .lesson,
			.period2: .freePeriod,
			.recess: .recess,
			.period3: .freePeriod,
			.period4: .freePeriod,
			.lunch: .lunch,
			.period5: .freePeriod,
			.period6: .freePeriod,
			.finished: .finished,
		]

		for transition in SchoolDayTransition.allCases {
			let projection = projector.projection(for: transition, on: base, dayIndex: 4, subjects: subjects)
			#expect(projection.content.phase == expected[transition])
		}
	}

	@Test("Before school and lesson content match Current Subject intent semantics")
	func currentSubjectContent() throws {
		let projector = SchoolDayActivityProjector(calendar: calendar)
		let base = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 8)))
		let subjects = [subject(name: "Maths", period: 1), subject(name: "English", period: 2)]

		let morning = projector.projection(for: .morning, on: base, dayIndex: 4, subjects: subjects).content
		#expect(morning.title == "Before School")
		#expect(morning.symbol == "function")
		#expect(morning.nextText == "First Period: Maths")
		#expect(calendar.component(.hour, from: try #require(morning.endDate)) == 8)
		#expect(calendar.component(.minute, from: try #require(morning.endDate)) == 50)

		let period = projector.projection(for: .period1, on: base, dayIndex: 4, subjects: subjects).content
		#expect(period.title == "Maths")
		#expect(period.nextText == "Next: English")
	}

	@Test("Missing subjects become free periods")
	func freePeriod() throws {
		let projector = SchoolDayActivityProjector(calendar: calendar)
		let base = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 9, minute: 48)))
		let content = projector.projection(for: .period2, on: base, dayIndex: 4, subjects: []).content
		#expect(content.phase == .freePeriod)
		#expect(content.title == "Free Period")
		#expect(content.symbol == "studentdesk")
	}

	@Test("Scheduler transition matching is exact to the minute")
	func dueTransition() throws {
		let exact = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 10, minute: 46)))
		let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 10, minute: 47)))
		#expect(SchoolDayTransition.due(at: exact, calendar: calendar) == .recess)
		#expect(SchoolDayTransition.due(at: late, calendar: calendar) == nil)
	}

	@Test("School calendar excludes weekends and holidays")
	func schoolCalendarFiltering() throws {
		let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3)))
		let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
		let holiday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
		#expect(SchoolCalendar.configured.isSchoolDay(friday))
		#expect(!SchoolCalendar.configured.isSchoolDay(saturday))
		#expect(!SchoolCalendar.configured.isSchoolDay(holiday))
	}

	private func subject(name: String, period: Int) -> TimetableSubjectDTO {
		let session = [1: 0, 2: 1, 3: 3, 4: 4, 5: 6, 6: 7][period]!
		return TimetableSubjectDTO(
			id: name,
			symbol: "function",
			colour: .init(r: 0.2, g: 0.4, b: 0.8, a: 1),
			slots: [.init(day: 4, session: session)],
			classroom: .unknown(rawLocation: "Unknown classroom"),
			teacher: .unknown(rawNotes: "Unknown teacher")
		)
	}
}
