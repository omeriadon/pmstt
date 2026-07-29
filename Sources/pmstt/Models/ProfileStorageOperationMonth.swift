import Fluent
import Vapor

final class ProfileStorageOperationMonth: Model, @unchecked Sendable {
	static let schema = "profile_storage_operation_months"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "year_month")
	var yearMonth: String

	@Field(key: "reserved_operations")
	var reservedOperations: Int

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(id: UUID? = nil, yearMonth: String, reservedOperations: Int = 0) {
		self.id = id
		self.yearMonth = yearMonth
		self.reservedOperations = reservedOperations
	}
}
