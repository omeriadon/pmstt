import Fluent

struct CreateReceivedPassMirror: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("received_pass_mirrors")
			.id()
			.field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
			.field("pass_serial_number", .string, .required)
			.field("issuer_account_id", .string, .required)
			.field("source_kind", .string, .required)
			.field("signed_display_name", .string, .required)
			.field("author_display_name", .string)
			.field("subjects_data", .data, .required)
			.field("is_deleted", .bool, .required)
			.field("wallet_revision", .int, .required)
			.field("received_at", .datetime, .required)
			.field("pass_updated_at", .datetime, .required)
			.field("content_revision", .int, .required)
			.field("updated_at", .datetime)
			.unique(on: "user_id", "pass_serial_number")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("received_pass_mirrors").delete()
	}
}
