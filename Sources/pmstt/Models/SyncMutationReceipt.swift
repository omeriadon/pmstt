import Fluent
import Vapor

final class SyncMutationReceipt: Model, @unchecked Sendable {
	static let schema = "sync_mutation_receipts"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "mutation_id")
	var mutationID: UUID

	@Field(key: "result_data")
	var resultData: Data

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: UUID,
		mutationID: UUID,
		resultData: Data
	) {
		self.id = id
		$user.id = userID
		self.mutationID = mutationID
		self.resultData = resultData
	}
}
