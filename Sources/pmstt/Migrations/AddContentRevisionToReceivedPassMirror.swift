import Fluent

struct AddContentRevisionToReceivedPassMirror: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("received_pass_mirrors")
			.field("content_revision", .int, .required, .custom("DEFAULT 1"))
			.update()

		// If you need to make it required, you might need to set a default value first for existing rows or just leave it optional if that's safe, but let's assume setting it to a default.
		// For a clean dev fix, if data loss is fine, we could drop the table, but adding the field is safer.
	}

	func revert(on database: any Database) async throws {
		try await database.schema("received_pass_mirrors")
			.deleteField("content_revision")
			.update()
	}
}
