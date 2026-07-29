import Fluent
import Vapor

enum BroadcastNotificationDeliveryState: String, Codable, Sendable {
	case pending
	case completed
	case failed
}

final class BroadcastNotificationRecord: Model, Content, @unchecked Sendable {
	static let schema = "broadcast_notification_records"

	@ID(key: .id)
	var id: UUID?

	@OptionalField(key: "sender_account_id")
	var senderAccountID: UUID?

	@Field(key: "sender_email")
	var senderEmail: String

	@Field(key: "sender_authority")
	var senderAuthority: AccountAuthority

	@Field(key: "audience")
	var audience: String

	@Field(key: "title")
	var title: String

	@OptionalField(key: "subtitle")
	var subtitle: String?

	@OptionalField(key: "body")
	var body: String?

	@Field(key: "eligible_device_count")
	var eligibleDeviceCount: Int

	@Field(key: "delivered_device_count")
	var deliveredDeviceCount: Int

	@Field(key: "invalidated_device_count")
	var invalidatedDeviceCount: Int

	@Field(key: "failed_device_count")
	var failedDeviceCount: Int

	@Field(key: "delivery_state")
	var deliveryState: BroadcastNotificationDeliveryState

	@OptionalField(key: "failure_summary")
	var failureSummary: String?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		senderAccountID: UUID?,
		senderEmail: String,
		senderAuthority: AccountAuthority,
		audience: String,
		title: String,
		subtitle: String?,
		body: String?,
		eligibleDeviceCount: Int = 0
	) {
		self.id = id
		self.senderAccountID = senderAccountID
		self.senderEmail = senderEmail
		self.senderAuthority = senderAuthority
		self.audience = audience
		self.title = title
		self.subtitle = subtitle
		self.body = body
		self.eligibleDeviceCount = eligibleDeviceCount
		deliveredDeviceCount = 0
		invalidatedDeviceCount = 0
		failedDeviceCount = 0
		deliveryState = .pending
	}
}
