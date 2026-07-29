import Fluent
import Vapor

final class ProfileMedia: Model, @unchecked Sendable {
	static let schema = "profile_media"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "object_key")
	var objectKey: String

	@Field(key: "content_type")
	var contentType: String

	@Field(key: "byte_size")
	var byteSize: Int

	@Field(key: "width")
	var width: Int

	@Field(key: "height")
	var height: Int

	@Field(key: "checksum")
	var checksum: String

	@Field(key: "revision")
	var revision: Int

	@Field(key: "etag")
	var etag: String

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: UUID,
		objectKey: String,
		contentType: String,
		byteSize: Int,
		width: Int,
		height: Int,
		checksum: String,
		revision: Int,
		etag: String
	) {
		self.id = id
		$user.id = userID
		self.objectKey = objectKey
		self.contentType = contentType
		self.byteSize = byteSize
		self.width = width
		self.height = height
		self.checksum = checksum
		self.revision = revision
		self.etag = etag
	}
}
