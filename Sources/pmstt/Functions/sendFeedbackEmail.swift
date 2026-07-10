import Vapor

func sendFeedbackEmail(body: FeedbackRequest, reporterUser: User, req: Request) async throws -> Response {
	let reporterID = reporterUser.id?.uuidString ?? "unknown"
	let html = """
	<h1>Timetable App Feedback</h1>
	<p><strong>Category:</strong> \(escapeFeedbackHTML(body.category))</p>
	<p><strong>Reporter ID:</strong> \(escapeFeedbackHTML(reporterID))</p>
	<p><strong>Message:</strong></p>
	<p>\(escapeFeedbackHTML(body.message).replacingOccurrences(of: "\n", with: "<br>"))</p>
	<p><strong>Generated:</strong> \(Date().description)</p>
	"""
	let email = ResendEmailRequest(
		from: "onboarding@resend.dev",
		to: "adon.omeri@student.education.wa.edu.au",
		subject: "Timetable App Feedback: \(body.category)",
		html: html
	)
	let response = try await req.client.post(
		URI(string: "https://api.resend.com/emails"),
		headers: [
			"Authorization": "Bearer \(resendAPIKey)",
			"Content-Type": "application/json",
		]
	) { clientReq in
		try clientReq.content.encode(email)
	}
	guard response.status == .ok || response.status == .created else {
		throw Abort(.badGateway, reason: "Email failed to send.")
	}
	return Response(status: .created)
}

private func escapeFeedbackHTML(_ value: String) -> String {
	value
		.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "<", with: "&lt;")
		.replacingOccurrences(of: ">", with: "&gt;")
		.replacingOccurrences(of: "\"", with: "&quot;")
}
