import Foundation

enum SchoolDayActivityPhase: String, Codable {
	case beforeSchool
	case lesson
	case freePeriod
	case recess
	case lunch
	case finished
}

struct SchoolDayActivityColor: Codable {
	let r: Double
	let g: Double
	let b: Double
	let a: Double

	static let blue = Self(r: 0, g: 0.478, b: 1, a: 1)
	static let orange = Self(r: 1, g: 0.584, b: 0, a: 1)
	static let indigo = Self(r: 0.345, g: 0.337, b: 0.839, a: 1)
}

struct SchoolDayActivityAttributesPayload: Codable {
	let activityKey: String
	let schoolDate: String
}

struct SchoolDayActivityContentState: Codable {
	let phase: SchoolDayActivityPhase
	let title: String
	let symbol: String
	let color: SchoolDayActivityColor
	let nextText: String?
	let startDate: Date?
	let endDate: Date?
}

enum LiveActivityEvent: String, Codable {
	case start
	case update
	case end
}

struct LiveActivityPayload: Encodable {
	let aps: APS

	struct APS: Encodable {
		let timestamp: Int
		let event: LiveActivityEvent
		let contentState: SchoolDayActivityContentState
		let staleDate: Int?
		let dismissalDate: Int?
		let attributesType: String?
		let attributes: SchoolDayActivityAttributesPayload?
		let inputPushToken: Int?
		let alert: Alert?

		enum CodingKeys: String, CodingKey {
			case timestamp
			case event
			case contentState = "content-state"
			case staleDate = "stale-date"
			case dismissalDate = "dismissal-date"
			case attributesType = "attributes-type"
			case attributes
			case inputPushToken = "input-push-token"
			case alert
		}
	}

	struct Alert: Encodable {
		let title: String
		let body: String
	}
}
