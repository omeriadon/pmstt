import Fluent
import Vapor

enum SchoolDayLiveActivityStatus: String, Codable, Sendable {
	case active
	case ended
}

final class SchoolDayLiveActivity: Model, Content, @unchecked Sendable {
	static let schema = "school_day_live_activities"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_device_id")
	var userDevice: UserDevice

	@Field(key: "activity_key")
	var activityKey: String

	@Field(key: "school_date")
	var schoolDate: String

	@OptionalField(key: "update_token")
	var updateToken: String?

	@Field(key: "current_transition")
	var currentTransition: String

	@Field(key: "status")
	var status: SchoolDayLiveActivityStatus

	@OptionalField(key: "last_apns_timestamp")
	var lastAPNSTimestamp: Date?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userDeviceID: UserDevice.IDValue,
		activityKey: String,
		schoolDate: String,
		updateToken: String? = nil,
		currentTransition: String,
		status: SchoolDayLiveActivityStatus = .active,
		lastAPNSTimestamp: Date? = nil
	) {
		self.id = id
		$userDevice.id = userDeviceID
		self.activityKey = activityKey
		self.schoolDate = schoolDate
		self.updateToken = updateToken
		self.currentTransition = currentTransition
		self.status = status
		self.lastAPNSTimestamp = lastAPNSTimestamp
	}
}
