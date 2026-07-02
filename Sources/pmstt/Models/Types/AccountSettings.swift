import Foundation
import Vapor

enum NotificationLeadTime: Int, Content, CaseIterable, Hashable {
	case zero = 0
	case one = 1
	case two = 2
	case three = 3
	case four = 4
	case five = 5

	var minutes: Int { rawValue }
}

struct AccountSettings: Content, Hashable {
	var liveActivitiesEnabled: Bool
	var notificationsEnabled: Bool
	var broadcastNotificationsEnabled: Bool
	var notificationLeadTime: NotificationLeadTime

	static var `default`: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: true,
			notificationsEnabled: false,
			broadcastNotificationsEnabled: true,
			notificationLeadTime: .zero
		)
	}
}

extension AccountSettings {
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let defaults = Self.default

		liveActivitiesEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveActivitiesEnabled) ?? defaults.liveActivitiesEnabled
		notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
		broadcastNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .broadcastNotificationsEnabled) ?? defaults.broadcastNotificationsEnabled
		notificationLeadTime = try container.decodeIfPresent(NotificationLeadTime.self, forKey: .notificationLeadTime) ?? defaults.notificationLeadTime
	}
}
