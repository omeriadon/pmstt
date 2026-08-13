import Fluent

struct AddCalendarEventWeather: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(CalendarEvent.schema)
			.field("shows_weather", .bool, .required, .sql(.default(false)))
			.update()

		try await database.schema(SchoolWeatherCache.schema)
			.field("precipitation_chance", .double, .required, .sql(.default(0)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SchoolWeatherCache.schema)
			.deleteField("precipitation_chance")
			.update()

		try await database.schema(CalendarEvent.schema)
			.deleteField("shows_weather")
			.update()
	}
}
