import Fluent
import Vapor

final class ProfileStorageQuota: Model, @unchecked Sendable {
	static let schema = "profile_storage_quota"
	static let singletonID = UUID(uuid: (0x5D, 0x23, 0x7C, 0xBA, 0xB0, 0x4A, 0x46, 0xB5, 0x9E, 0xC8, 0x73, 0xA1, 0x7A, 0xB5, 0xA4, 0x12))

	@ID(key: .id)
	var id: UUID?

	@Field(key: "stored_bytes")
	var storedBytes: Int64

	@Field(key: "reserved_bytes")
	var reservedBytes: Int64

	@Field(key: "writes_disabled")
	var writesDisabled: Bool

	@OptionalField(key: "reconciled_stored_bytes")
	var reconciledStoredBytes: Int64?

	@Field(key: "reconciliation_warning")
	var reconciliationWarning: Bool

	@Timestamp(key: "reconciled_at", on: .none)
	var reconciledAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		storedBytes: Int64 = 0,
		reservedBytes: Int64 = 0,
		writesDisabled: Bool = false,
		reconciledStoredBytes: Int64? = nil,
		reconciliationWarning: Bool = false
	) {
		id = Self.singletonID
		self.storedBytes = storedBytes
		self.reservedBytes = reservedBytes
		self.writesDisabled = writesDisabled
		self.reconciledStoredBytes = reconciledStoredBytes
		self.reconciliationWarning = reconciliationWarning
	}
}
