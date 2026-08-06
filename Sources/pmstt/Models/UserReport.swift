import Fluent
import Foundation

enum ModerationAction: String, Codable {
	case pending
	case noAction
	case accountDeleted
	case approved
	case rejected
}

final class UserReport: Model {
	static let schema = "user_reports"

	@ID(key: .id) var id: UUID?
	// Keep these identifiers after either account is deleted. Moderation history
	// is an audit record, not part of the account's cascading data.
	@Field(key: "reporter_id") var reporterID: UUID
	@Field(key: "reported_user_id") var reportedUserID: UUID
	@Field(key: "action") var action: ModerationAction
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	@Timestamp(key: "acted_at", on: .update) var actedAt: Date?
	init() {}
	init(reporterID: UUID, reportedUserID: UUID) {
		self.reporterID = reporterID
		self.reportedUserID = reportedUserID
		action = .pending
	}
}
