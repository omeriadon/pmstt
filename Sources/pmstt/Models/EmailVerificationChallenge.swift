import Fluent
import Vapor

final class EmailVerificationChallenge: Model, Content, @unchecked Sendable {
	static let schema = "email_verification_challenges"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "normalized_email")
	var normalizedEmail: String

	@Field(key: "code_hash")
	var codeHash: String

	@Field(key: "installation_id")
	var installationID: String

	@Field(key: "source_ip")
	var sourceIP: String

	@Field(key: "expires_at")
	var expiresAt: Date

	@Field(key: "resend_available_at")
	var resendAvailableAt: Date

	@OptionalField(key: "used_at")
	var usedAt: Date?

	@OptionalField(key: "last_attempt_at")
	var lastAttemptAt: Date?

	@Field(key: "failed_attempt_count")
	var failedAttemptCount: Int

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(
		normalizedEmail: String,
		codeHash: String,
		installationID: String,
		sourceIP: String,
		expiresAt: Date,
		resendAvailableAt: Date
	) {
		self.normalizedEmail = normalizedEmail
		self.codeHash = codeHash
		self.installationID = installationID
		self.sourceIP = sourceIP
		self.expiresAt = expiresAt
		self.resendAvailableAt = resendAvailableAt
		failedAttemptCount = 0
	}
}
