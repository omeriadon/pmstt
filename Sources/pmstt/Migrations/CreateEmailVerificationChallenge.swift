import Fluent

struct CreateEmailVerificationChallenge: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(EmailVerificationChallenge.schema)
			.id()
			.field("normalized_email", .string, .required)
			.field("code_hash", .string, .required)
			.field("installation_id", .string, .required)
			.field("source_ip", .string, .required)
			.field("expires_at", .datetime, .required)
			.field("resend_available_at", .datetime, .required)
			.field("used_at", .datetime)
			.field("last_attempt_at", .datetime)
			.field("failed_attempt_count", .int, .required)
			.field("created_at", .datetime)
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(EmailVerificationChallenge.schema).delete()
	}
}
