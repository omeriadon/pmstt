import Fluent
import Vapor

final class OwnerTimetable: Model, Content, @unchecked Sendable {
	static let schema = "owner_timetables"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "subjects_data")
	var subjectsData: Data

	@Field(key: "revision")
	var revision: Int

	@Field(key: "is_searchable")
	var isSearchable: Bool

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(id: UUID? = nil, userID: User.IDValue, subjectsData: Data, revision: Int, isSearchable: Bool = true) {
		self.id = id
		$user.id = userID
		self.subjectsData = subjectsData
		self.revision = revision
		self.isSearchable = isSearchable
	}
}
