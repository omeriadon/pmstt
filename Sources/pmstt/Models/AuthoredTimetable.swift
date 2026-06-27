import Fluent
import Vapor

final class AuthoredTimetable: Model, Content, @unchecked Sendable {
	static let schema = "authored_timetables"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "author_user_id")
	var author: User

	@Field(key: "subject_display_name")
	var subjectDisplayName: String

	@Field(key: "pass_serial_number")
	var passSerialNumber: String

	@Field(key: "subjects_data")
	var subjectsData: Data

	@Field(key: "revision")
	var revision: Int

	@Field(key: "is_deleted")
	var isDeleted: Bool

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		authorUserID: User.IDValue,
		subjectDisplayName: String,
		passSerialNumber: String,
		subjectsData: Data,
		revision: Int,
		isDeleted: Bool = false
	) {
		self.id = id
		self.$author.id = authorUserID
		self.subjectDisplayName = subjectDisplayName
		self.passSerialNumber = passSerialNumber
		self.subjectsData = subjectsData
		self.revision = revision
		self.isDeleted = isDeleted
	}
}
