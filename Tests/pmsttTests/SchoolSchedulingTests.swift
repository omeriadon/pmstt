@testable import pmstt
import XCTest

final class SchoolSchedulingTests: XCTestCase {
	private var calendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Australia/Perth")!
		return calendar
	}

	func testSelectedNotificationLeadTimesHaveDistinctDueMinutesAndMatchingLabels() {
		let event = SchoolNotificationEvent.period2

		XCTAssertTrue(event.isDue(hour: 9, minute: 43, leadMinutes: 5, dayIndex: 0))
		XCTAssertFalse(event.isDue(hour: 9, minute: 43, leadMinutes: 2, dayIndex: 0))
		XCTAssertTrue(event.isDue(hour: 9, minute: 46, leadMinutes: 2, dayIndex: 0))
		XCTAssertTrue(event.isDue(hour: 9, minute: 48, leadMinutes: 0, dayIndex: 0))

		let content = event.content(dayIndex: 0, subjects: [], leadMinutes: 5)
		XCTAssertTrue(content.title.contains("in 5 minutes"))
		XCTAssertFalse(content.title.contains("in 2 minutes"))
	}

	func testNotificationExpirationIsThreeMinutesAfterSend() {
		let sentAt = Date(timeIntervalSince1970: 1_000)
		XCTAssertEqual(
			NotificationService.apnsExpiration(sentAt: sentAt).timeIntervalSince(sentAt),
			180
		)
	}

	func testShortDaysReplacePeriodSixWithFinish() throws {
		let wednesday = try date(2026, 7, 22, 14, 32)
		XCTAssertEqual(
			SchoolDayTransition.due(at: wednesday, dayIndex: 2, calendar: calendar),
			.finished
		)
		XCTAssertFalse(
			SchoolNotificationEvent.period6.couldBeDue(
				hour: 14,
				minute: 27,
				dayIndex: 2
			)
		)
		XCTAssertTrue(
			SchoolNotificationEvent.finished.isDue(
				hour: 14,
				minute: 27,
				leadMinutes: 5,
				dayIndex: 2
			)
		)

		let projection = SchoolDayActivityProjector(calendar: calendar).projection(
			for: .period5,
			on: wednesday,
			dayIndex: 2,
			subjects: []
		)
		XCTAssertEqual(projection.content.nextText, "Last Period")
	}

	func testRegularDaysRetainPeriodSixAndLaterFinish() throws {
		let monday = try date(2026, 7, 20, 14, 32)
		XCTAssertEqual(
			SchoolDayTransition.due(at: monday, dayIndex: 0, calendar: calendar),
			.period6
		)
		XCTAssertEqual(
			SchoolDayTransition.current(
				at: try date(2026, 7, 20, 15, 30),
				dayIndex: 0,
				calendar: calendar
			),
			.finished
		)
	}

	private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
		try XCTUnwrap(calendar.date(from: DateComponents(
			year: year,
			month: month,
			day: day,
			hour: hour,
			minute: minute
		)))
	}
}
