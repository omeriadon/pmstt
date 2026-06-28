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
	var liveActivityStartTime: TimeOfDay
	var liveActivityEndTime: TimeOfDay
	var liveActivityWeekdays: Set<SchoolWeekday>
	var showBreaksInLiveActivity: Bool
	var showNextSubjectInLiveActivity: Bool
	var widgetShowsReceivedTimetables: Bool
	var spotlightIndexingEnabled: Bool
	var siriAccessEnabled: Bool

	static var `default`: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: true,
			liveActivityStartTime: TimeOfDay(hour: 8, minute: 0),
			liveActivityEndTime: TimeOfDay(hour: 15, minute: 40),
			liveActivityWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
			showBreaksInLiveActivity: true,
			showNextSubjectInLiveActivity: true,
			widgetShowsReceivedTimetables: true,
			spotlightIndexingEnabled: true,
			siriAccessEnabled: true
		)
	}
}
