import Fluent
import Vapor

final class TimetableShareAlias: Model, Content, @unchecked Sendable {
	static let schema = "timetable_share_aliases"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "alias")
	var alias: String

	@Parent(key: "owner_timetable_id")
	var ownerTimetable: OwnerTimetable

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(id: UUID? = nil, alias: String, ownerTimetableID: OwnerTimetable.IDValue) {
		self.id = id
		self.alias = alias
		$ownerTimetable.id = ownerTimetableID
	}
}
