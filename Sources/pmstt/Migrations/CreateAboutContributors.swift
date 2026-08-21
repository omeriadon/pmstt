import Fluent

struct CreateAboutContributors: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(AboutContributor.schema)
			.id()
			.field("name", .string, .required)
			.field("role", .string, .required)
			.field("sort_order", .int, .required)
			.create()

		for (sortOrder, contributor) in [
			("Adon Omeri", "Software Engineer"),
			("Bob Han-Busi", "Human Interface Design"),
			("Joshua Gilgallon", "Infrastructure & Hosting"),
		].enumerated() {
			try await AboutContributor(
				name: contributor.0,
				role: contributor.1,
				sortOrder: sortOrder
			).create(on: database)
		}
	}

	func revert(on database: any Database) async throws {
		try await database.schema(AboutContributor.schema).delete()
	}
}
