import Fluent
import Vapor

final class SchoolNotificationDelivery: Model, Content, @unchecked Sendable {
	static let schema = "school_notification_deliveries"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "school_date")
	var schoolDate: String

	@Field(key: "event")
	var event: String

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(id: UUID? = nil, userID: User.IDValue, schoolDate: String, event: String) {
		self.id = id
		self.$user.id = userID
		self.schoolDate = schoolDate
		self.event = event
	}
}
