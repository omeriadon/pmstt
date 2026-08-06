import Foundation
import Vapor

enum LocationStatus: String, Codable, Sendable {
	case onCampus
	case offCampus
}

struct LocationStatusItem: Content, Hashable, Sendable {
	let state: LocationStatus
	let updatedAt: Date
}
