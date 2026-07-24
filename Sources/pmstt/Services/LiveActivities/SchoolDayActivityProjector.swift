import Foundation

enum SchoolDayTransition: String, CaseIterable, Equatable {
	case morning
	case period1
	case period2
	case recess
	case period3
	case period4
	case lunch
	case period5
	case period6
	case finished

	var time: (hour: Int, minute: Int) {
		switch self {
			case .morning: (8, 0)
			case .period1: (8, 50)
			case .period2: (9, 48)
			case .recess: (10, 46)
			case .period3: (11, 8)
			case .period4: (12, 6)
			case .lunch: (13, 4)
			case .period5: (13, 34)
			case .period6: (14, 32)
			case .finished: (15, 30)
		}
	}

	static func due(at date: Date, calendar: Calendar) -> Self? {
		due(at: date, dayIndex: nil, calendar: calendar)
	}

	static func due(at date: Date, dayIndex: Int?, calendar: Calendar) -> Self? {
		let hour = calendar.component(.hour, from: date)
		let minute = calendar.component(.minute, from: date)
		if let dayIndex, isShortDay(dayIndex) {
			if (hour, minute) == dismissalTime(for: dayIndex) {
				return .finished
			}
			if (hour, minute) == period6.time {
				return nil
			}
		}
		return allCases.first { $0.time == (hour, minute) }
	}

	static func current(at date: Date, calendar: Calendar) -> Self? {
		current(at: date, dayIndex: nil, calendar: calendar)
	}

	static func current(at date: Date, dayIndex: Int?, calendar: Calendar) -> Self? {
		let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
		if let dayIndex, currentMinutes >= minutes(dismissalTime(for: dayIndex)) {
			return .finished
		}
		return allCases.last { transition in
			if let dayIndex, isShortDay(dayIndex), transition == .period6 {
				return false
			}
			return transition.time.hour * 60 + transition.time.minute <= currentMinutes
		}
	}

	static func hasReachedDismissal(at date: Date, dayIndex: Int, calendar: Calendar) -> Bool {
		let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
		return currentMinutes >= minutes(dismissalTime(for: dayIndex))
	}

	static func dismissalTime(for dayIndex: Int) -> (hour: Int, minute: Int) {
		isShortDay(dayIndex) ? period6.time : finished.time
	}

	static func isShortDay(_ dayIndex: Int) -> Bool {
		dayIndex == 2 || dayIndex == 4
	}

	private static func minutes(_ time: (hour: Int, minute: Int)) -> Int {
		time.hour * 60 + time.minute
	}
}

struct SchoolDayActivityProjection {
	let transition: SchoolDayTransition
	let content: SchoolDayActivityContentState
	let staleDate: Date?
}

struct SchoolDayActivityProjector {
	let calendar: Calendar

	init(calendar: Calendar = SchoolCalendar.configured.calendar) {
		self.calendar = calendar
	}

	func projection(
		for transition: SchoolDayTransition,
		on date: Date,
		dayIndex: Int,
		subjects: [TimetableSubjectDTO]
	) -> SchoolDayActivityProjection {
		let content: SchoolDayActivityContentState

		switch transition {
			case .morning:
				let first = subject(period: 1, dayIndex: dayIndex, subjects: subjects)
				content = .init(
					phase: .beforeSchool,
					title: "Before School",
					symbol: first?.symbol ?? "studentdesk",
					color: color(first),
					nextText: "First Period: \(first?.id ?? "Free Period")",
					startDate: self.date(on: date, hour: 8, minute: 0),
					endDate: self.date(on: date, hour: 8, minute: 50)
				)
			case .period1: content = lesson(period: 1, date: date, dayIndex: dayIndex, subjects: subjects, next: nextSubjectText(period: 2, dayIndex: dayIndex, subjects: subjects), end: (9, 48))
			case .period2: content = lesson(period: 2, date: date, dayIndex: dayIndex, subjects: subjects, next: "Recess", end: (10, 46))
			case .recess: content = breakState(.recess, date: date, nextPeriod: 3, dayIndex: dayIndex, subjects: subjects, end: (11, 8))
			case .period3: content = lesson(period: 3, date: date, dayIndex: dayIndex, subjects: subjects, next: nextSubjectText(period: 4, dayIndex: dayIndex, subjects: subjects), end: (12, 6))
			case .period4: content = lesson(period: 4, date: date, dayIndex: dayIndex, subjects: subjects, next: "Lunch", end: (13, 4))
			case .lunch: content = breakState(.lunch, date: date, nextPeriod: 5, dayIndex: dayIndex, subjects: subjects, end: (13, 34))
			case .period5:
				content = lesson(
					period: 5,
					date: date,
					dayIndex: dayIndex,
					subjects: subjects,
					next: SchoolDayTransition.isShortDay(dayIndex) ? "Last Period" : nextSubjectText(period: 6, dayIndex: dayIndex, subjects: subjects),
					end: (14, 32)
				)
			case .period6:
				content = SchoolDayTransition.isShortDay(dayIndex)
					? finishedContent()
					: lesson(period: 6, date: date, dayIndex: dayIndex, subjects: subjects, next: "Last Period", end: (15, 30))
			case .finished:
				content = finishedContent()
		}

		return SchoolDayActivityProjection(
			transition: transition,
			content: content,
			staleDate: content.endDate.map { $0.addingTimeInterval(60) }
		)
	}

	private func lesson(period: Int, date baseDate: Date, dayIndex: Int, subjects: [TimetableSubjectDTO], next: String?, end: (Int, Int)) -> SchoolDayActivityContentState {
		let current = subject(period: period, dayIndex: dayIndex, subjects: subjects)
		return .init(
			phase: current == nil ? .freePeriod : .lesson,
			title: current?.id ?? "Free Period",
			symbol: current?.symbol ?? "studentdesk",
			color: color(current),
			nextText: next,
			startDate: date(on: baseDate, hour: SchoolDayTransition.allCases[period].time.hour, minute: SchoolDayTransition.allCases[period].time.minute),
			endDate: date(on: baseDate, hour: end.0, minute: end.1)
		)
	}

	private func breakState(_ phase: SchoolDayActivityPhase, date baseDate: Date, nextPeriod: Int, dayIndex: Int, subjects: [TimetableSubjectDTO], end: (Int, Int)) -> SchoolDayActivityContentState {
		let transition: SchoolDayTransition = phase == .recess ? .recess : .lunch
		return .init(
			phase: phase,
			title: phase == .recess ? "Recess" : "Lunch",
			symbol: phase == .recess ? "cup.and.saucer.fill" : "takeoutbag.and.cup.and.straw.fill",
			color: .orange,
			nextText: nextSubjectText(period: nextPeriod, dayIndex: dayIndex, subjects: subjects),
			startDate: date(on: baseDate, hour: transition.time.hour, minute: transition.time.minute),
			endDate: date(on: baseDate, hour: end.0, minute: end.1)
		)
	}

	private func nextSubjectText(period: Int, dayIndex: Int, subjects: [TimetableSubjectDTO]) -> String {
		subject(period: period, dayIndex: dayIndex, subjects: subjects)?.id ?? "Free Period"
	}

	private func subject(period: Int, dayIndex: Int, subjects: [TimetableSubjectDTO]) -> TimetableSubjectDTO? {
		guard let session = [1: 0, 2: 1, 3: 3, 4: 4, 5: 6, 6: 7][period] else { return nil }
		return subjects.first { subject in
			subject.slots.contains { $0.day == dayIndex && $0.session == session }
		}
	}

	private func color(_ subject: TimetableSubjectDTO?) -> SchoolDayActivityColor {
		guard let color = subject?.colour else { return .blue }
		return .init(r: color.r, g: color.g, b: color.b, a: color.a)
	}

	private func finishedContent() -> SchoolDayActivityContentState {
		.init(phase: .finished, title: "School's Out", symbol: "house.fill", color: .indigo, nextText: nil, startDate: nil, endDate: nil)
	}

	private func date(on baseDate: Date, hour: Int, minute: Int) -> Date {
		calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? baseDate
	}
}
