import Fluent
import Foundation

final class SyncRecordTombstone: Model, @unchecked Sendable {
	static let schema = "sync_record_tombstones"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "record_type")
	var recordType: SyncRecordType

	@Field(key: "record_id")
	var recordID: UUID

	@Field(key: "revision")
	var revision: Int

	@Timestamp(key: "deleted_at", on: .create)
	var deletedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: UUID,
		recordType: SyncRecordType,
		recordID: UUID,
		revision: Int
	) {
		self.id = id
		$user.id = userID
		self.recordType = recordType
		self.recordID = recordID
		self.revision = revision
	}
}
