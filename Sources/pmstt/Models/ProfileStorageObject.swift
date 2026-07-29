import Fluent
import Vapor

enum ProfileStorageObjectState: String, Codable {
	case reserved
	case active
	case superseded
	case orphaned
}

final class ProfileStorageObject: Model, @unchecked Sendable {
	static let schema = "profile_storage_objects"

	@ID(key: .id)
	var id: UUID?

	@OptionalParent(key: "user_id")
	var user: User?

	@Field(key: "object_key")
	var objectKey: String

	@Field(key: "byte_size")
	var byteSize: Int

	@Enum(key: "state")
	var state: ProfileStorageObjectState

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: UUID?,
		objectKey: String,
		byteSize: Int,
		state: ProfileStorageObjectState
	) {
		self.id = id
		$user.id = userID
		self.objectKey = objectKey
		self.byteSize = byteSize
		self.state = state
	}
}
