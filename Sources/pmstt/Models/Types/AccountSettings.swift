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
	var notificationsEnabled: Bool

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
			siriAccessEnabled: true,
			notificationsEnabled: false
		)
	}
}

extension AccountSettings {
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let defaults = Self.default

		liveActivitiesEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveActivitiesEnabled) ?? defaults.liveActivitiesEnabled
		liveActivityStartTime = try container.decodeIfPresent(TimeOfDay.self, forKey: .liveActivityStartTime) ?? defaults.liveActivityStartTime
		liveActivityEndTime = try container.decodeIfPresent(TimeOfDay.self, forKey: .liveActivityEndTime) ?? defaults.liveActivityEndTime
		liveActivityWeekdays = try container.decodeIfPresent(Set<SchoolWeekday>.self, forKey: .liveActivityWeekdays) ?? defaults.liveActivityWeekdays
		showBreaksInLiveActivity = try container.decodeIfPresent(Bool.self, forKey: .showBreaksInLiveActivity) ?? defaults.showBreaksInLiveActivity
		showNextSubjectInLiveActivity = try container.decodeIfPresent(Bool.self, forKey: .showNextSubjectInLiveActivity) ?? defaults.showNextSubjectInLiveActivity
		widgetShowsReceivedTimetables = try container.decodeIfPresent(Bool.self, forKey: .widgetShowsReceivedTimetables) ?? defaults.widgetShowsReceivedTimetables
		spotlightIndexingEnabled = try container.decodeIfPresent(Bool.self, forKey: .spotlightIndexingEnabled) ?? defaults.spotlightIndexingEnabled
		siriAccessEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriAccessEnabled) ?? defaults.siriAccessEnabled
		notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
	}
}
