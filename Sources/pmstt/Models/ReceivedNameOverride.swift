import Fluent
import Vapor

final class ReceivedNameOverride: Model, Content, @unchecked Sendable {
	static let schema = "received_name_overrides"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "pass_serial_number")
	var passSerialNumber: String

	@Field(key: "display_name")
	var displayName: String

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: User.IDValue,
		passSerialNumber: String,
		displayName: String
	) {
		self.id = id
		$user.id = userID
		self.passSerialNumber = passSerialNumber
		self.displayName = displayName
	}
}
