import Fluent

struct CreateAuthorityAuditRecord: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(AuthorityAuditRecord.schema)
			.id()
			.field("actor_user_id", .uuid, .required)
			.field("target_user_id", .uuid, .required)
			.field("old_authority", .string, .required)
			.field("new_authority", .string, .required)
			.field("created_at", .datetime)
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(AuthorityAuditRecord.schema).delete()
	}
}
