import Fluent

struct CreateProfileMedia: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(ProfileMedia.schema)
			.id()
			.field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
			.field("object_key", .string, .required)
			.field("content_type", .string, .required)
			.field("byte_size", .int, .required)
			.field("width", .int, .required)
			.field("height", .int, .required)
			.field("checksum", .string, .required)
			.field("revision", .int, .required)
			.field("etag", .string, .required)
			.field("updated_at", .datetime)
			.unique(on: "user_id")
			.unique(on: "object_key")
			.create()

		try await database.schema(ProfileStorageObject.schema)
			.id()
			.field("user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
			.field("object_key", .string, .required)
			.field("byte_size", .int, .required)
			.field("state", .string, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "object_key")
			.create()

		try await database.schema(ProfileStorageQuota.schema)
			.id()
			.field("stored_bytes", .int64, .required)
			.field("reserved_bytes", .int64, .required)
			.field("writes_disabled", .bool, .required)
			.field("reconciled_stored_bytes", .int64)
			.field("reconciliation_warning", .bool, .required)
			.field("reconciled_at", .datetime)
			.field("updated_at", .datetime)
			.create()

		try await database.schema(ProfileStorageOperationMonth.schema)
			.id()
			.field("year_month", .string, .required)
			.field("reserved_operations", .int, .required)
			.field("updated_at", .datetime)
			.unique(on: "year_month")
			.create()

		try await ProfileStorageQuota().create(on: database)
	}

	func revert(on database: any Database) async throws {
		try await database.schema(ProfileStorageOperationMonth.schema).delete()
		try await database.schema(ProfileStorageQuota.schema).delete()
		try await database.schema(ProfileStorageObject.schema).delete()
		try await database.schema(ProfileMedia.schema).delete()
	}
}
