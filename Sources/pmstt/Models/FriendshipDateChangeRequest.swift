import Fluent

final class FriendshipDateChangeRequest: Model {
	static let schema = "friendship_date_change_requests"

	@ID(key: .id) var id: UUID?
	// Keep the request even after a friendship or requester is removed.
	@Field(key: "friendship_id") var friendshipID: UUID
	@Field(key: "requester_id") var requesterID: UUID
	@Field(key: "requested_date") var requestedDate: Date
	@Field(key: "action") var action: ModerationAction
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	@Timestamp(key: "acted_at", on: .update) var actedAt: Date?
	init() {}
	init(friendshipID: UUID, requesterID: UUID, requestedDate: Date) {
		self.friendshipID = friendshipID
		self.requesterID = requesterID
		self.requestedDate = requestedDate
		action = .pending
	}
}
