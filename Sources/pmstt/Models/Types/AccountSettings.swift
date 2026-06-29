import Foundation
import Vapor

struct AccountSettings: Content, Hashable {
	var liveActivitiesEnabled: Bool
	var notificationsEnabled: Bool

	static var `default`: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: true,
			notificationsEnabled: false
		)
	}
}

extension AccountSettings {
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let defaults = Self.default

		liveActivitiesEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveActivitiesEnabled) ?? defaults.liveActivitiesEnabled
		notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
	}
}
