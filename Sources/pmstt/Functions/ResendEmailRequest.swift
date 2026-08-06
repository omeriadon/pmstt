import Vapor

let resendAPIKey = Environment.get("RESEND_API_KEY")!

struct ResendEmailRequest: Content {
	let from: String
	let to: [String]
	let subject: String
	let html: String
}
