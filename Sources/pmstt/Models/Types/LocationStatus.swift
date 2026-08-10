import Foundation
import Vapor

enum LocationStatus: String, Codable, Sendable {
	case offCampus
	case withinTenMinutes
	case withinFiveMinutes
	case onCampus
}

enum LocationNotificationPreference: String, Codable, CaseIterable, Hashable, Sendable {
	case withinTenMinutes
	case withinFiveMinutes
	case arrived
}

struct LocationStatusItem: Content, Hashable, Sendable {
	let state: LocationStatus
	let updatedAt: Date
}
