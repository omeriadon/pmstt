import Fluent

struct CreateSchoolCalendarEntry: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SchoolCalendarEntry.schema)
			.id().field("kind", .string, .required).field("label", .string, .required)
			.field("start_date", .string, .required).field("end_date", .string).create()
		try await SchoolCalendarEntry(kind: "term", label: "Term 3", startDate: "2026-07-20", endDate: "2026-09-25").create(on: database)
		try await SchoolCalendarEntry(kind: "term", label: "Term 4", startDate: "2026-10-12", endDate: "2026-12-17").create(on: database)
		try await SchoolCalendarEntry(kind: "noSchool", label: "Labour Day", startDate: "2026-03-02").create(on: database)
		try await SchoolCalendarEntry(kind: "noSchool", label: "Western Australia Day", startDate: "2026-06-01").create(on: database)
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SchoolCalendarEntry.schema).delete()
	}
}
