import Fluent
import Vapor

final class PassRecord: Model, Content, @unchecked Sendable {
	static let schema = "pass_records"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "serial_number")
	var serialNumber: String

	@Field(key: "issuer_account_id")
	var issuerAccountID: String

	@Field(key: "source_kind")
	private var sourceKindRawValue: String

	var sourceKind: SourceKind {
		get { SourceKind(rawValueOrDefault: sourceKindRawValue) }
		set { sourceKindRawValue = newValue.rawValue }
	}

	@OptionalParent(key: "authored_timetable_id")
	var authoredTimetable: AuthoredTimetable?

	@Field(key: "revision")
	var revision: Int

	@Field(key: "authentication_token_hash")
	var authenticationTokenHash: String

	@Field(key: "is_deleted")
	var isDeleted: Bool

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		serialNumber: String,
		issuerAccountID: String,
		sourceKind: SourceKind,
		authoredTimetableID: AuthoredTimetable.IDValue? = nil,
		revision: Int,
		authenticationTokenHash: String,
		isDeleted: Bool = false
	) {
		self.id = id
		self.serialNumber = serialNumber
		self.issuerAccountID = issuerAccountID
		sourceKindRawValue = sourceKind.rawValue
		$authoredTimetable.id = authoredTimetableID
		self.revision = revision
		self.authenticationTokenHash = authenticationTokenHash
		self.isDeleted = isDeleted
	}
}
