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

enum AppFontDesign: String, Content, CaseIterable, Hashable {
	case monospaced
	case rounded
	case expanded
}

struct AccountSettings: Content, Hashable {
	var liveActivitiesEnabled: Bool
	var appFontDesign: AppFontDesign
	var appBackground: AppBackground
	var futureEventRange: FutureEventRange
	var watchBleedEnabled: Bool
	var notificationsEnabled: Bool
	var broadcastNotificationsEnabled: Bool
	var notificationLeadTimes: Set<NotificationLeadTime>
	var breakToPeriodNotificationLeadTimes: Set<NotificationLeadTime>
	var eventNotificationSchedules: Set<EventNotificationSchedule>
	var calendarEventAutoDeleteDays: Int
	var serverRevision: Int

	static var `default`: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: true,
			appFontDesign: .monospaced,
			appBackground: .blackPaper,
			futureEventRange: .oneMonth,
			watchBleedEnabled: true,
			notificationsEnabled: true,
			broadcastNotificationsEnabled: true,
			notificationLeadTimes: [.zero],
			breakToPeriodNotificationLeadTimes: [.zero],
			eventNotificationSchedules: [],
			calendarEventAutoDeleteDays: 0,
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
		appFontDesign = try container.decodeIfPresent(AppFontDesign.self, forKey: .appFontDesign) ?? defaults.appFontDesign
		appBackground = try container.decodeIfPresent(AppBackground.self, forKey: .appBackground) ?? defaults.appBackground
		futureEventRange = try container.decodeIfPresent(FutureEventRange.self, forKey: .futureEventRange) ?? defaults.futureEventRange
		watchBleedEnabled = try container.decodeIfPresent(Bool.self, forKey: .watchBleedEnabled) ?? defaults.watchBleedEnabled
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
		calendarEventAutoDeleteDays = try container.decodeIfPresent(Int.self, forKey: .calendarEventAutoDeleteDays) ?? defaults.calendarEventAutoDeleteDays
		serverRevision = try container.decodeIfPresent(Int.self, forKey: .serverRevision) ?? 0
	}
}

struct EventNotificationSchedule: Content, Hashable {
	let hour: Int
	let minute: Int
	let dayOffset: Int
}
