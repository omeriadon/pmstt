import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
	static let schema = "users"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "email")
	var email: String?

	@Field(key: "password_hash")
	var passwordHash: String?

	@Field(key: "apple_subject")
	var appleSubject: String?

	@Field(key: "apple_email_forwarding_enabled")
	var appleEmailForwardingEnabled: Bool?

	@Field(key: "apple_authorization_revoked_at")
	var appleAuthorizationRevokedAt: Date?

	@Field(key: "display_name")
	var displayName: String

	@Field(key: "self_pass_serial_number")
	var selfPassSerialNumber: String

	@Field(key: "settings_data")
	var settingsData: Data

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		email: String? = nil,
		passwordHash: String? = nil,
		appleSubject: String? = nil,
		appleEmailForwardingEnabled: Bool? = nil,
		appleAuthorizationRevokedAt: Date? = nil,
		displayName: String,
		selfPassSerialNumber: String,
		settingsData: Data
	) {
		self.id = id
		self.email = email?.lowercased()
		self.passwordHash = passwordHash
		self.appleSubject = appleSubject
		self.appleEmailForwardingEnabled = appleEmailForwardingEnabled
		self.appleAuthorizationRevokedAt = appleAuthorizationRevokedAt
		self.displayName = displayName
		self.selfPassSerialNumber = selfPassSerialNumber
		self.settingsData = settingsData
	}
}
