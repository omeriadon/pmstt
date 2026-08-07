import SwiftSMTP
import Vapor

func sendVerificationEmail(
	code: String,
	to email: String
) async throws {
	let password = Environment.get("SMTP_PASSWORD") ?? ""
	guard !password.isEmpty else {
		throw Abort(.internalServerError, reason: "SMTP_PASSWORD is not configured.")
	}

	let smtp = SMTP(
		hostname: "smtp.purelymail.com",
		email: "timetable@jdqc.dev",
		password: password,
		port: 465,
		tlsMode: .requireTLS
	)
	let mail = Mail(
		from: Mail.User(email: "timetable@jdqc.dev"),
		to: [Mail.User(email: email)],
		subject: "Your Timetable verification code",
		text: "Verify your Timetable account.\n\n"
			+ "Your six-digit verification code is: "
			+ code
			+ "\n\nThis code expires in ten minutes."
	)

	try await withCheckedThrowingContinuation { continuation in
		smtp.send(mail) { error in
			if let error {
				continuation.resume(throwing: error)
			} else {
				continuation.resume()
			}
		}
	}
}
