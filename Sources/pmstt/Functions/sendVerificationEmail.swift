import Fluent
import Vapor

func sendVerificationEmail(
	code: String,
	to email: String,
	on database: any Database
) async throws {
	try await sendLoggedEmail(
		to: email,
		subject: "Your Timetable verification code",
		body: "Verify your Timetable account.\n\n"
			+ "Your six-digit verification code is: "
			+ code
			+ "\n\nThis code expires in ten minutes.",
		on: database
	)
}
