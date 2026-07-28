import Fluent
import Vapor

enum FriendshipStatus: String, Codable, Sendable {
	case pending
	case accepted
	case blocked
}

final class Friendship: Model, Content, @unchecked Sendable {
	static let schema = "friendships"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "requester_id")
	var requester: User

	@Parent(key: "recipient_id")
	var recipient: User

	@Field(key: "status")
	var status: FriendshipStatus

	@OptionalField(key: "accepted_at")
	var acceptedAt: Date?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		requesterID: User.IDValue,
		recipientID: User.IDValue,
		status: FriendshipStatus = .pending,
		acceptedAt: Date? = nil
	) {
		self.id = id
		$requester.id = requesterID
		$recipient.id = recipientID
		self.status = status
		self.acceptedAt = acceptedAt
	}
}
