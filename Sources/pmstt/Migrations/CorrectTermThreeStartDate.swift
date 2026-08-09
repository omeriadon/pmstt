import Fluent

struct CorrectTermThreeStartDate: AsyncMigration {
	func prepare(on database: any Database) async throws {
		let staleEntries = try await SchoolCalendarEntry.query(on: database)
			.filter(\.$kind == "term")
			.filter(\.$label == "Term 3")
			.filter(\.$startDate == "2026-07-07")
			.all()

		for entry in staleEntries {
			entry.startDate = "2026-07-20"
			try await entry.update(on: database)
		}
	}

	func revert(on _: any Database) async throws {}
}
