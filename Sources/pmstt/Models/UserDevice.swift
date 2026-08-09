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

	@OptionalField(key: "os_major_version")
	var osMajorVersion: Int?

	@OptionalField(key: "os_minor_version")
	var osMinorVersion: Int?

	@Field(key: "apns_token")
	var apnsToken: String?

	@Field(key: "is_debug")
	var isDebug: Bool

	@Field(key: "is_beta")
	var isBeta: Bool

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
		osMajorVersion: Int? = nil,
		osMinorVersion: Int? = nil,
		apnsToken: String? = nil,
		isDebug: Bool = false,
		isBeta: Bool = false,
		liveActivityPushToStartToken: String? = nil,
		lastSeenAt: Date = Date()
	) {
		self.id = id
		$user.id = userID
		self.installationID = installationID
		self.platform = platform
		self.osMajorVersion = osMajorVersion
		self.osMinorVersion = osMinorVersion
		self.apnsToken = apnsToken
		self.isDebug = isDebug
		self.isBeta = isBeta
		self.liveActivityPushToStartToken = liveActivityPushToStartToken
		self.lastSeenAt = lastSeenAt
	}
}
