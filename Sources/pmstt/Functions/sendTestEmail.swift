import SwiftSMTP
import Vapor

func sendAdministrationTestEmail() async throws {
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
		to: [Mail.User(email: "omeriadon@outlook.com")],
		subject: "Timetable test email",
		text: "This is a test email sent from Timetable system administration."
	)

	try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
		smtp.send(mail) { error in
			if let error {
				continuation.resume(throwing: error)
			} else {
				continuation.resume()
			}
		}
	}
}
