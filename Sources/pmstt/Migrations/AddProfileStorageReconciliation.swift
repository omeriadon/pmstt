import Fluent
import SQLKit

private enum ProfileStorageReconciliationMigrationError: Error {
	case sqlDatabaseRequired
}

struct AddProfileStorageReconciliation: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sql = database as? any SQLDatabase else {
			throw ProfileStorageReconciliationMigrationError.sqlDatabaseRequired
		}
		try await sql.raw(
			"""
			ALTER TABLE "profile_storage_quota"
			ADD COLUMN IF NOT EXISTS "reconciled_stored_bytes" BIGINT,
			ADD COLUMN IF NOT EXISTS "reconciliation_warning" BOOLEAN NOT NULL DEFAULT FALSE,
			ADD COLUMN IF NOT EXISTS "reconciled_at" TIMESTAMPTZ
			"""
		).run()
	}

	func revert(on database: any Database) async throws {
		guard let sql = database as? any SQLDatabase else {
			throw ProfileStorageReconciliationMigrationError.sqlDatabaseRequired
		}
		try await sql.raw(
			"""
			ALTER TABLE "profile_storage_quota"
			DROP COLUMN IF EXISTS "reconciled_at",
			DROP COLUMN IF EXISTS "reconciliation_warning",
			DROP COLUMN IF EXISTS "reconciled_stored_bytes"
			"""
		).run()
	}
}
