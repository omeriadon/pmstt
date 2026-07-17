import Fluent
import Vapor

final class ReceivedTimetableImport: Model, Content, @unchecked Sendable {
	static let schema = "received_timetable_imports"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "timetable_id")
	var timetableID: UUID

	@Field(key: "source_kind")
	var sourceKind: SourceKind

	@Field(key: "imported_at")
	var importedAt: Date

	@OptionalField(key: "revoked_at")
	var revokedAt: Date?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(id: UUID? = nil, userID: User.IDValue, timetableID: UUID, sourceKind: SourceKind, importedAt: Date = .now, revokedAt: Date? = nil) {
		self.id = id
		$user.id = userID
		self.timetableID = timetableID
		self.sourceKind = sourceKind
		self.importedAt = importedAt
		self.revokedAt = revokedAt
	}
}
