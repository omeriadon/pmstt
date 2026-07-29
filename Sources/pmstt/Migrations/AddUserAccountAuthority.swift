import Fluent

struct AddUserAccountAuthority: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("account_authority", .string)
			.update()

		try await User.query(on: database)
			.set(\.$accountAuthority, to: .user)
			.update()

		for email in AccountAuthority.systemOwnerEmails {
			try await User.query(on: database)
				.filter(\.$email == email)
				.set(\.$accountAuthority, to: .systemOwner)
				.update()
		}

		try await database.schema(User.schema)
			.field("account_authority", .string, .required)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.deleteField("account_authority")
			.update()
	}
}
