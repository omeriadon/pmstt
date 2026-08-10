import Fluent

struct CreateSchoolWeatherCache: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SchoolWeatherCache.schema)
			.id()
			.field("temperature_celsius", .double, .required)
			.field("condition_code", .string, .required)
			.field("uv_index", .int, .required)
			.field("observed_at", .datetime, .required)
			.field("fetched_at", .datetime, .required)
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SchoolWeatherCache.schema).delete()
	}
}
