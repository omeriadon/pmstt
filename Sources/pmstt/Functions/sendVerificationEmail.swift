import Vapor

func sendVerificationEmail(
	code: String,
	to email: String,
	req: Request
) async throws {
	let request = ResendEmailRequest(
		from: "Timetable <onboarding@resend.dev>",
		to: email,
		subject: "Your Timetable verification code",
		html: """
		<h1>Verify your Timetable account</h1>
		<p>Your six-digit verification code is:</p>
		<p style=\"font-size: 28px; font-weight: 700; letter-spacing: 0.2em;\">\(code)</p>
		<p>This code expires in ten minutes.</p>
		"""
	)
	let response = try await req.client.post(
		URI(string: "https://api.resend.com/emails"),
		headers: [
			"Authorization": "Bearer \(resendAPIKey)",
			"Content-Type": "application/json",
		]
	) { clientRequest in
		try clientRequest.content.encode(request)
	}

	guard response.status == .ok || response.status == .created else {
		throw Abort(.badGateway, reason: "Verification email failed to send.")
	}
}
