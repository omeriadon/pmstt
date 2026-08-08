import Fluent
import Foundation
import Vapor

struct SchoolCalendarDate: Content, Hashable {
	let year: Int
	let month: Int
	let day: Int

	init(_ components: DateComponents) {
		year = components.year ?? 0
		month = components.month ?? 0
		day = components.day ?? 0
	}
}

struct SchoolCalendarDateRange: Content, Hashable {
	let label: String
	let start: SchoolCalendarDate
	let end: SchoolCalendarDate
}

struct SchoolCalendarNamedDate: Content, Hashable {
	let date: SchoolCalendarDate
	let label: String
}

struct SchoolCalendarResponse: Content {
	let termRanges: [SchoolCalendarDateRange]
	let skippedDates: [SchoolCalendarNamedDate]
}

struct SchoolCalendar {
	struct DateRange {
		let label: String
		let start: DateComponents
		let end: DateComponents
	}

	struct NamedDate {
		let date: DateComponents
		let label: String
	}

	static let perthTimeZone = TimeZone(identifier: "Australia/Perth")!

	/// WA public-school student term dates. Update this configuration before each school year.
	static let configured = SchoolCalendar(
		termRanges: [
			.init(label: "Term 3", start: .ymd(2026, 7, 20), end: .ymd(2026, 9, 25)),
			.init(label: "Term 4", start: .ymd(2026, 10, 12), end: .ymd(2026, 12, 17)),
		],
		excludedDates: [
			.init(date: .ymd(2026, 3, 2), label: "Labour Day"),
			.init(date: .ymd(2026, 6, 1), label: "Western Australia Day"),
			.init(date: .ymd(2026, 7, 26), label: "No school"),
		]
	)

	let termRanges: [DateRange]
	let excludedDates: [NamedDate]
	let calendar: Calendar

	init(termRanges: [DateRange], excludedDates: [NamedDate]) {
		self.termRanges = termRanges
		self.excludedDates = excludedDates
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = Self.perthTimeZone
		self.calendar = calendar
	}

	func isSchoolDay(_ date: Date) -> Bool {
		let components = dayComponents(for: date)
		guard let weekday = calendar.dateComponents([.weekday], from: date).weekday,
		      (2 ... 6).contains(weekday),
		      !excludedDates.contains(where: { excluded in
		      	excluded.date.year == components.year && excluded.date.month == components.month && excluded.date.day == components.day
		      }),
		      let day = calendar.date(from: components)
		else { return false }

		return termRanges.contains { range in
			guard let start = calendar.date(from: range.start), let end = calendar.date(from: range.end) else { return false }
			return day >= start && day <= end
		}
	}

	func dayComponents(for date: Date) -> DateComponents {
		calendar.dateComponents([.year, .month, .day], from: date)
	}

	func dayIndex(for date: Date) -> Int? {
		guard let weekday = calendar.dateComponents([.weekday], from: date).weekday,
		      (2 ... 6).contains(weekday)
		else { return nil }
		return weekday - 2
	}

	var response: SchoolCalendarResponse {
		SchoolCalendarResponse(
			termRanges: termRanges.map { range in
				SchoolCalendarDateRange(label: range.label, start: SchoolCalendarDate(range.start), end: SchoolCalendarDate(range.end))
			},
			skippedDates: excludedDates.map { SchoolCalendarNamedDate(date: SchoolCalendarDate($0.date), label: $0.label) }
		)
	}

	static func response(on database: any Database) async throws -> SchoolCalendarResponse {
		let entries = try await SchoolCalendarEntry.query(on: database).all()
		guard !entries.isEmpty else { return configured.response }
		let terms = try entries.filter { $0.kind == "term" }.map { entry in
			try SchoolCalendarDateRange(label: entry.label, start: SchoolCalendarDate(storageValue: entry.startDate), end: SchoolCalendarDate(storageValue: entry.endDate ?? entry.startDate))
		}
		let skipped = try entries.filter { $0.kind == "noSchool" }.map { entry in
			try SchoolCalendarNamedDate(date: SchoolCalendarDate(storageValue: entry.startDate), label: entry.label)
		}
		return SchoolCalendarResponse(
			termRanges: terms.isEmpty ? configured.response.termRanges : terms,
			skippedDates: skipped
		)
	}
}

private extension DateComponents {
	static func ymd(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
		DateComponents(year: year, month: month, day: day)
	}
}

private extension SchoolCalendarDate {
	init(storageValue: String) throws {
		let values = storageValue.split(separator: "-").compactMap { Int($0) }
		guard values.count == 3 else { throw Abort(.internalServerError) }
		year = values[0]; month = values[1]; day = values[2]
	}
}
