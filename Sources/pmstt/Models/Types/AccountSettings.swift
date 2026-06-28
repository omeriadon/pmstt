import Foundation
import Vapor

struct TimeOfDay: Codable, Hashable {
	var hour: Int
	var minute: Int
}

enum SchoolWeekday: String, Codable, Hashable {
	case monday, tuesday, wednesday, thursday, friday, saturday, sunday
}

struct AccountSettings: Content, Hashable {
	var liveActivitiesEnabled: Bool

	static var `default`: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: true
		)
	}
}
