import Fluent
import Foundation

final class EmailDeliveryRecord: Model, @unchecked Sendable {
	static let schema = "email_delivery_records"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "recipient")
	var recipient: String

	@Field(key: "subject")
	var subject: String

	@Field(key: "body")
	var body: String

	@Field(key: "status")
	var status: String

	@OptionalField(key: "failure_reason")
	var failureReason: String?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(recipient: String, subject: String, body: String) {
		self.recipient = recipient
		self.subject = subject
		self.body = body
		status = "sending"
	}
}
