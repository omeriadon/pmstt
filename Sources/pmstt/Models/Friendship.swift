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

	@Field(key: "pair_key")
	var pairKey: String

	@Field(key: "status")
	var status: FriendshipStatus

	@OptionalField(key: "accepted_at")
	var acceptedAt: Date?

	@Field(key: "requester_sort_order")
	var requesterSortOrder: Int

	@Field(key: "recipient_sort_order")
	var recipientSortOrder: Int

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	static func pairKey(for first: UUID, and second: UUID) -> String {
		[first.uuidString.lowercased(), second.uuidString.lowercased()]
			.sorted()
			.joined(separator: ":")
	}

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
		pairKey = Self.pairKey(for: requesterID, and: recipientID)
		self.status = status
		self.acceptedAt = acceptedAt
		requesterSortOrder = 0
		recipientSortOrder = 0
	}
}
