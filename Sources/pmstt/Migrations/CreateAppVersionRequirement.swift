import Fluent

struct CreateAppVersionRequirement: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(AppVersionRequirement.schema)
			.id()
			.field("app_version", .string, .required)
			.field("app_build", .int, .required)
			.field("mac_version", .string, .required)
			.field("mac_build", .int, .required)
			.create()

		try await AppVersionRequirement().create(on: database)
	}

	func revert(on database: any Database) async throws {
		try await database.schema(AppVersionRequirement.schema).delete()
	}
}
