import Foundation
import Vapor

enum NotificationLeadTime: Int, Content, CaseIterable, Hashable {
	case zero = 0
	case one = 1
	case two = 2
	case three = 3
	case four = 4
	case five = 5
	case ten = 10

	var minutes: Int {
		rawValue
	}
}

struct AccountSettings: Content, Hashable {
	var liveActivitiesEnabled: Bool
	var highlightsCurrentDay: Bool
	var notificationsEnabled: Bool
	var broadcastNotificationsEnabled: Bool
	var notificationLeadTimes: Set<NotificationLeadTime>
	var breakToPeriodNotificationLeadTimes: Set<NotificationLeadTime>
	var eventNotificationSchedules: Set<EventNotificationSchedule>
	var serverRevision: Int

	static var `default`: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: true,
			highlightsCurrentDay: true,
			notificationsEnabled: true,
			broadcastNotificationsEnabled: true,
			notificationLeadTimes: [.zero],
			breakToPeriodNotificationLeadTimes: [.zero],
			eventNotificationSchedules: [],
			serverRevision: 0
		)
	}
}

extension AccountSettings {
	private enum LegacyCodingKeys: String, CodingKey {
		case notificationLeadTime
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let defaults = Self.default

		liveActivitiesEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveActivitiesEnabled) ?? defaults.liveActivitiesEnabled
		highlightsCurrentDay = try container.decodeIfPresent(Bool.self, forKey: .highlightsCurrentDay) ?? defaults.highlightsCurrentDay
		notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
		broadcastNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .broadcastNotificationsEnabled) ?? defaults.broadcastNotificationsEnabled
		if let leadTimes = try container.decodeIfPresent(Set<NotificationLeadTime>.self, forKey: .notificationLeadTimes) {
			notificationLeadTimes = leadTimes
		} else if let legacyLeadTime = try decoder.container(keyedBy: LegacyCodingKeys.self).decodeIfPresent(NotificationLeadTime.self, forKey: .notificationLeadTime) {
			notificationLeadTimes = [legacyLeadTime]
		} else {
			notificationLeadTimes = defaults.notificationLeadTimes
		}
		breakToPeriodNotificationLeadTimes = try container.decodeIfPresent(Set<NotificationLeadTime>.self, forKey: .breakToPeriodNotificationLeadTimes) ?? defaults.breakToPeriodNotificationLeadTimes
		eventNotificationSchedules = try container.decodeIfPresent(Set<EventNotificationSchedule>.self, forKey: .eventNotificationSchedules) ?? defaults.eventNotificationSchedules
		serverRevision = try container.decodeIfPresent(Int.self, forKey: .serverRevision) ?? 0
	}
}

struct EventNotificationSchedule: Content, Hashable {
	let hour: Int
	let minute: Int
	let dayOffset: Int
}
