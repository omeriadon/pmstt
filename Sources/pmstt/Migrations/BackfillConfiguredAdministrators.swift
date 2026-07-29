import Fluent
import Vapor

struct BackfillConfiguredAdministrators: AsyncMigration {
	func prepare(on database: any Database) async throws {
		let configuredEmails = Set(
			(Environment.get("TIMETABLE_EVENT_ADMIN_EMAILS") ?? "")
				.split(separator: ",")
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
		)

		for email in configuredEmails where !AccountAuthority.systemOwnerEmails.contains(email) {
			try await User.query(on: database)
				.filter(\.$email == email)
				.set(\.$accountAuthority, to: .administrator)
				.update()
		}
	}

	func revert(on _: any Database) async throws {}
}
