import Fluent
import Vapor

final class ReceivedPassMirror: Model, Content, @unchecked Sendable {
	static let schema = "received_pass_mirrors"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "pass_serial_number")
	var passSerialNumber: String

	@Field(key: "issuer_account_id")
	var issuerAccountID: String

	@Field(key: "source_kind")
	var sourceKind: String

	@Field(key: "signed_display_name")
	var signedDisplayName: String

	@Field(key: "author_display_name")
	var authorDisplayName: String?

	@Field(key: "subjects_data")
	var subjectsData: Data

	@Field(key: "is_deleted")
	var isDeleted: Bool

	@Field(key: "wallet_revision")
	var walletRevision: Int

	@Field(key: "received_at")
	var receivedAt: Date

	@Field(key: "pass_updated_at")
	var passUpdatedAt: Date

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: User.IDValue,
		passSerialNumber: String,
		issuerAccountID: String,
		sourceKind: String,
		signedDisplayName: String,
		authorDisplayName: String? = nil,
		subjectsData: Data,
		isDeleted: Bool = false,
		walletRevision: Int,
		receivedAt: Date,
		passUpdatedAt: Date
	) {
		self.id = id
		self.$user.id = userID
		self.passSerialNumber = passSerialNumber
		self.issuerAccountID = issuerAccountID
		self.sourceKind = sourceKind
		self.signedDisplayName = signedDisplayName
		self.authorDisplayName = authorDisplayName
		self.subjectsData = subjectsData
		self.isDeleted = isDeleted
		self.walletRevision = walletRevision
		self.receivedAt = receivedAt
		self.passUpdatedAt = passUpdatedAt
	}
}
