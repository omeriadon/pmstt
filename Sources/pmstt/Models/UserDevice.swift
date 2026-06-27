import Fluent
import Vapor

final class UserDevice: Model, Content, @unchecked Sendable {
	static let schema = "user_devices"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "installation_id")
	var installationID: String

	@Field(key: "platform")
	var platform: String

	@Field(key: "apns_token")
	var apnsToken: String?

	@Field(key: "live_activity_push_to_start_token")
	var liveActivityPushToStartToken: String?

	@Field(key: "last_seen_at")
	var lastSeenAt: Date

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: User.IDValue,
		installationID: String,
		platform: String,
		apnsToken: String? = nil,
		liveActivityPushToStartToken: String? = nil,
		lastSeenAt: Date = Date()
	) {
		self.id = id
		self.$user.id = userID
		self.installationID = installationID
		self.platform = platform
		self.apnsToken = apnsToken
		self.liveActivityPushToStartToken = liveActivityPushToStartToken
		self.lastSeenAt = lastSeenAt
	}
}
