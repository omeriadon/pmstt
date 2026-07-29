import Fluent
import SQLKit

struct AddUserAccountAuthority: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			throw AccountAuthorityMigrationError.unsupportedDatabase
		}

		if sqlDatabase.dialect.name == "postgresql" {
			try await sqlDatabase.raw("ALTER TABLE \"users\" ADD COLUMN IF NOT EXISTS \"account_authority\" TEXT").run()
		} else {
			try await database.schema(User.schema)
				.field("account_authority", .string)
				.update()
		}

		try await User.query(on: database)
			.set(\.$accountAuthority, to: .user)
			.update()

		for email in AccountAuthority.systemOwnerEmails {
			try await User.query(on: database)
				.filter(\.$email == email)
				.set(\.$accountAuthority, to: .systemOwner)
				.update()
		}

		if sqlDatabase.dialect.name == "postgresql" {
			try await sqlDatabase.raw("ALTER TABLE \"users\" ALTER COLUMN \"account_authority\" SET NOT NULL").run()
		}
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.deleteField("account_authority")
			.update()
	}
}

private enum AccountAuthorityMigrationError: Error {
	case unsupportedDatabase
}
