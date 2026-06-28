//
//  sendReportEmail.swift
//  pmstt
//
//  Created by Adon Omeri on 28/6/2026.
//

import Vapor

let resendAPIKey = "re_GSwEFAdz_H52TxxRZbeNekpR5me3Bkizn"

struct ResendEmailRequest: Content {
	let from: String
	let to: String
	let subject: String
	let html: String
}

func sendReportEmail(body: ReportUserRequest, req: Request) async throws -> HTTPStatus {
	let email = ResendEmailRequest(
		from: "onboarding@resend.dev",
		to: "adon.omeri@student.education.wa.edu.au",
		subject: "Timetable App Report Request",
		html: """
		<h1>Timetable App Report</h1>
		<p><strong>Reported Account ID:</strong> \(body.reportedAccountID)</p>
		<p><strong>Reporter Account ID:</strong> \(body.reportedAccountID)</p>
		"""
	)

	let response = try await req.client.post(
		URI(string: "https://api.resend.com/emails"),
		headers: [
			"Authorization": "Bearer \(resendAPIKey)",
			"Content-Type": "application/json"
		]
	) { clientReq in
		try clientReq.content.encode(email)
	}

	guard response.status == HTTPStatus.ok || response.status == HTTPStatus.created else {
		let responseBody = response.body.map { buffer in
			String(buffer: buffer)
		} ?? "No response body"

		req.logger.error("Resend email failed with status \(response.status): \(responseBody)")

		throw Abort(.badGateway, reason: "Email failed to send.")
	}

	return .created
}
