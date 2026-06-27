import Fluent
import Vapor

final class PassRegistration: Model, Content, @unchecked Sendable {
	static let schema = "pass_registrations"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "device_library_identifier")
	var deviceLibraryIdentifier: String

	@Field(key: "pass_type_identifier")
	var passTypeIdentifier: String

	@Field(key: "serial_number")
	var serialNumber: String

	@Field(key: "push_token")
	var pushToken: String

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		deviceLibraryIdentifier: String,
		passTypeIdentifier: String,
		serialNumber: String,
		pushToken: String
	) {
		self.id = id
		self.deviceLibraryIdentifier = deviceLibraryIdentifier
		self.passTypeIdentifier = passTypeIdentifier
		self.serialNumber = serialNumber
		self.pushToken = pushToken
	}
}
