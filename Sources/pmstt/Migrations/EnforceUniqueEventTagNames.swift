import Fluent
import SQLKit

private enum EventTagConstraintMigrationError: Error {
	case sqlDatabaseRequired
}

struct EnforceUniqueEventTagNames: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sql = database as? any SQLDatabase else {
			throw EventTagConstraintMigrationError.sqlDatabaseRequired
		}

		try await sql.raw(
			"""
			ALTER TABLE "event_tag_associated_names"
			ADD COLUMN IF NOT EXISTS "category" TEXT
			"""
		).run()
		try await sql.raw(
			"""
			ALTER TABLE "event_tag_associated_names"
			ADD COLUMN IF NOT EXISTS "is_active" BOOLEAN
			"""
		).run()
		try await sql.raw(
			"""
			UPDATE "event_tag_associated_names" AS names
			SET
				"category" = tags."category",
				"is_active" = NOT tags."is_archived"
			FROM "event_tags" AS tags
			WHERE names."event_tag_id" = tags."id"
			"""
		).run()
		try await sql.raw(
			"""
			ALTER TABLE "event_tag_associated_names"
			ALTER COLUMN "category" SET NOT NULL,
			ALTER COLUMN "is_active" SET NOT NULL
			"""
		).run()
		try await sql.raw(
			"""
			CREATE UNIQUE INDEX IF NOT EXISTS
				"uq_event_tag_active_category_name"
			ON "event_tag_associated_names" ("category", "normalized_name")
			WHERE "is_active" = TRUE
			"""
		).run()
	}

	func revert(on database: any Database) async throws {
		guard let sql = database as? any SQLDatabase else {
			throw EventTagConstraintMigrationError.sqlDatabaseRequired
		}

		try await sql.raw(
			"""
			DROP INDEX IF EXISTS "uq_event_tag_active_category_name"
			"""
		).run()
		try await database.schema(EventTagAssociatedName.schema)
			.deleteField("is_active")
			.deleteField("category")
			.update()
	}
}
