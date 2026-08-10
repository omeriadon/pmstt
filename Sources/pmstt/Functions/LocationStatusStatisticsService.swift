import Foundation

struct LocationStatusStatisticsService {
	private static let calendar: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Australia/Perth")!
		return calendar
	}()

	func averageArrival(for histories: [[LocationStatusItem]]) -> Double? {
		let firstArrivals = histories.flatMap(firstArrivalsByDay)
		guard !firstArrivals.isEmpty else {
			return nil
		}

		let total = firstArrivals.reduce(0, +)
		return total / Double(firstArrivals.count)
	}

	func averageArrivalBySchoolDay(for history: [LocationStatusItem]) -> [Double?] {
		let arrivals = firstArrivalsByDate(in: history)
		return (2 ... 6).map { weekday in
			let matching = arrivals.compactMap { date, seconds in
				Self.calendar.component(.weekday, from: date) == weekday ? seconds : nil
			}
			guard !matching.isEmpty else {
				return nil
			}
			return matching.reduce(0, +) / Double(matching.count)
		}
	}

	private func firstArrivalsByDay(in history: [LocationStatusItem]) -> [Double] {
		Array(firstArrivalsByDate(in: history).values)
	}

	private func firstArrivalsByDate(in history: [LocationStatusItem]) -> [Date: Double] {
		var firstArrivalByDay: [Date: Double] = [:]

		for item in history where item.state == .onCampus {
			let seconds = secondsSinceMidnight(for: item.updatedAt)
			guard Double(5 * 60 * 60) ... Double(10 * 60 * 60) ~= seconds else {
				continue
			}

			let day = Self.calendar.startOfDay(for: item.updatedAt)
			if let current = firstArrivalByDay[day] {
				firstArrivalByDay[day] = min(current, seconds)
			} else {
				firstArrivalByDay[day] = seconds
			}
		}

		return firstArrivalByDay
	}

	private func secondsSinceMidnight(for date: Date) -> Double {
		let components = Self.calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
		return Double(components.hour ?? 0) * 60 * 60
			+ Double(components.minute ?? 0) * 60
			+ Double(components.second ?? 0)
			+ Double(components.nanosecond ?? 0) / 1_000_000_000
	}
}
