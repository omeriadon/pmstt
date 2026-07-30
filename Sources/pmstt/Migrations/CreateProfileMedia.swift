import Fluent
import SQLKit

struct CreateProfileMedia: AsyncMigration {
	func prepare(on database: any Database) async throws {
		if let sqlDatabase = database as? any SQLDatabase,
		   sqlDatabase.dialect.name == "postgresql"
		{
			try await createPostgreSQLTables(on: sqlDatabase)
		} else {
			try await createTables(on: database)
		}

		guard try await ProfileStorageQuota.query(on: database).first() == nil else {
			return
		}

		try await ProfileStorageQuota(
			storedBytes: 0,
			reservedBytes: 0,
			writesDisabled: false,
			reconciliationWarning: false
		).create(on: database)
	}

	private func createTables(on database: any Database) async throws {
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
	}

	private func createPostgreSQLTables(on database: any SQLDatabase) async throws {
		try await database.raw(
			"""
			CREATE TABLE IF NOT EXISTS "profile_media" (
				"id" UUID PRIMARY KEY,
				"user_id" UUID NOT NULL REFERENCES "users" ("id") ON DELETE CASCADE,
				"object_key" TEXT NOT NULL,
				"content_type" TEXT NOT NULL,
				"byte_size" BIGINT NOT NULL,
				"width" BIGINT NOT NULL,
				"height" BIGINT NOT NULL,
				"checksum" TEXT NOT NULL,
				"revision" BIGINT NOT NULL,
				"etag" TEXT NOT NULL,
				"updated_at" TIMESTAMPTZ,
				CONSTRAINT "uq:profile_media.user_id" UNIQUE ("user_id"),
				CONSTRAINT "uq:profile_media.object_key" UNIQUE ("object_key")
			)
			"""
		).run()

		try await database.raw(
			"""
			CREATE TABLE IF NOT EXISTS "profile_storage_objects" (
				"id" UUID PRIMARY KEY,
				"user_id" UUID REFERENCES "users" ("id") ON DELETE SET NULL,
				"object_key" TEXT NOT NULL,
				"byte_size" BIGINT NOT NULL,
				"state" TEXT NOT NULL,
				"created_at" TIMESTAMPTZ,
				"updated_at" TIMESTAMPTZ,
				CONSTRAINT "uq:profile_storage_objects.object_key" UNIQUE ("object_key")
			)
			"""
		).run()

		try await database.raw(
			"""
			CREATE TABLE IF NOT EXISTS "profile_storage_quota" (
				"id" UUID PRIMARY KEY,
				"stored_bytes" BIGINT NOT NULL,
				"reserved_bytes" BIGINT NOT NULL,
				"writes_disabled" BOOLEAN NOT NULL,
				"reconciled_stored_bytes" BIGINT,
				"reconciliation_warning" BOOLEAN NOT NULL,
				"reconciled_at" TIMESTAMPTZ,
				"updated_at" TIMESTAMPTZ
			)
			"""
		).run()

		try await database.raw(
			"""
			CREATE TABLE IF NOT EXISTS "profile_storage_operation_months" (
				"id" UUID PRIMARY KEY,
				"year_month" TEXT NOT NULL,
				"reserved_operations" BIGINT NOT NULL,
				"updated_at" TIMESTAMPTZ,
				CONSTRAINT "uq:profile_storage_operation_months.year_month" UNIQUE ("year_month")
			)
			"""
		).run()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(ProfileStorageOperationMonth.schema).delete()
		try await database.schema(ProfileStorageQuota.schema).delete()
		try await database.schema(ProfileStorageObject.schema).delete()
		try await database.schema(ProfileMedia.schema).delete()
	}
}
