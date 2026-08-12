import Fluent
import SwiftSMTP
import Vapor

func sendLoggedEmail(
	to recipient: String,
	subject: String,
	body: String,
	on database: any Database
) async throws {
	let record = EmailDeliveryRecord(
		recipient: recipient,
		subject: subject,
		body: body
	)
	try await record.create(on: database)

	do {
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
			to: [Mail.User(email: recipient)],
			subject: subject,
			text: body
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

		record.status = "delivered"
		try await record.update(on: database)
	} catch {
		record.status = "failed"
		record.failureReason = String(describing: error)
		try? await record.update(on: database)
		throw error
	}
}
