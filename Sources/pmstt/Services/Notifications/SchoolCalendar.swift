import Foundation

struct SchoolCalendar {
	struct DateRange {
		let start: DateComponents
		let end: DateComponents
	}

	static let perthTimeZone = TimeZone(identifier: "Australia/Perth")!

	/// WA public-school student term dates. Update this configuration before each school year.
	static let configured = SchoolCalendar(
		termRanges: [
			// Term 3: started early (7 Jul) for development testing
			.init(start: .ymd(2026, 7, 7), end: .ymd(2026, 9, 25)),
			.init(start: .ymd(2026, 10, 12), end: .ymd(2026, 12, 17)),
		],
		excludedDates: [
			.ymd(2026, 3, 2), // Labour Day
			.ymd(2026, 6, 1), // Western Australia Day
		]
	)

	let termRanges: [DateRange]
	let excludedDates: Set<DateComponents>
	let calendar: Calendar

	init(termRanges: [DateRange], excludedDates: Set<DateComponents>) {
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
		      	excluded.year == components.year && excluded.month == components.month && excluded.day == components.day
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
}

private extension DateComponents {
	static func ymd(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
		DateComponents(year: year, month: month, day: day)
	}
}
