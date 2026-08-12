import Fluent

func sendAdministrationTestEmail(on database: any Database) async throws {
	try await sendLoggedEmail(
		to: "omeriadon@outlook.com",
		subject: "Timetable test email",
		body: "This is a test email sent from Timetable system administration.",
		on: database
	)
}
