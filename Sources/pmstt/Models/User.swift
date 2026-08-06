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

	@Field(key: "display_name")
	var displayName: String

	@Field(key: "self_pass_serial_number")
	var selfPassSerialNumber: String

	@Field(key: "settings_data")
	var settingsData: Data

	@Field(key: "settings_revision")
	var settingsRevision: Int

	@OptionalField(key: "profile_appearance_data")
	var profileAppearanceData: Data?

	@Field(key: "profile_revision")
	var profileRevision: Int

	@Field(key: "account_authority")
	var accountAuthority: AccountAuthority

	@OptionalField(key: "location_status_data")
	var locationStatusData: Data?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		email: String? = nil,
		passwordHash: String? = nil,
		displayName: String,
		selfPassSerialNumber: String,
		settingsData: Data,
		settingsRevision: Int = 0,
		profileAppearanceData: Data? = nil,
		profileRevision: Int = 0,
		accountAuthority: AccountAuthority = .user
	) {
		self.id = id
		self.email = email?.lowercased()
		self.passwordHash = passwordHash
		self.displayName = displayName
		self.selfPassSerialNumber = selfPassSerialNumber
		self.settingsData = settingsData
		self.settingsRevision = settingsRevision
		self.profileAppearanceData = profileAppearanceData
		self.profileRevision = profileRevision
		self.accountAuthority = accountAuthority
	}

	var resolvedAccountAuthority: AccountAuthority {
		AccountAuthority.resolved(for: email, storedAuthority: accountAuthority)
	}

	func locationStatusHistory() throws -> [LocationStatusItem] {
		guard let locationStatusData else {
			return []
		}

		return try JSONDecoder().decode([LocationStatusItem].self, from: locationStatusData)
	}

	func setLocationStatusHistory(_ history: [LocationStatusItem]) throws {
		locationStatusData = try JSONEncoder().encode(history)
	}
}
