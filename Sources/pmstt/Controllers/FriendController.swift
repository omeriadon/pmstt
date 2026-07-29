import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Vapor

struct FriendController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes.grouped("v1", "friends")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		protected.get(use: list)
		protected.get("requests", use: incomingRequests)
		protected.get("search", use: search)
		protected.get("profile", use: profileAppearance)
		protected.put("profile", use: updateProfileAppearance)
		protected.post("requests", use: createRequest)
		protected.post("requests", ":relationshipID", "accept", use: acceptRequest)
		protected.put("order", use: reorder)
		protected.get(":friendID", use: detail)
		protected.delete(":friendID", use: removeFriend)
		protected.post(":friendID", "block", use: blockFriend)
	}

	func list(req: Request) async throws -> [FriendSummaryDTO] {
		let userID = try req.auth.require(UserPayload.self).sub
		let relationships = try await Friendship.query(on: req.db)
			.group(.or) { group in
				group.filter(\.$requester.$id == userID)
				group.filter(\.$recipient.$id == userID)
			}
			.filter(\.$status == .accepted)
			.with(\.$requester)
			.with(\.$recipient)
			.sort(\.$acceptedAt, .descending)
			.all()
		let orderedRelationships = relationships.sorted {
			friendOrder(for: $0, viewerID: userID) < friendOrder(for: $1, viewerID: userID)
		}
		var summaries: [FriendSummaryDTO] = []
		for relationship in orderedRelationships {
			let summary = try await summary(for: relationship, viewerID: userID, on: req.db)
			summaries.append(summary)
		}
		return summaries
	}

	func reorder(req: Request) async throws -> [FriendSummaryDTO] {
		let userID = try req.auth.require(UserPayload.self).sub
		let request = try req.content.decode(FriendOrderUpdateRequest.self)
		let relationships = try await Friendship.query(on: req.db)
			.group(.or) { group in
				group.filter(\.$requester.$id == userID)
				group.filter(\.$recipient.$id == userID)
			}
			.filter(\.$status == .accepted)
			.all()
		let relationshipByFriendID = Dictionary(uniqueKeysWithValues: relationships.map { relationship in
			let friendID = relationship.$requester.id == userID ? relationship.$recipient.id : relationship.$requester.id
			return (friendID, relationship)
		})
		guard Set(request.friendIDs) == Set(relationshipByFriendID.keys), request.friendIDs.count == relationshipByFriendID.count else {
			throw Abort(.badRequest)
		}

		try await req.db.transaction { database in
			for (index, friendID) in request.friendIDs.enumerated() {
				guard let relationship = relationshipByFriendID[friendID] else {
					throw Abort(.badRequest)
				}
				if relationship.$requester.id == userID {
					relationship.requesterSortOrder = index
				} else {
					relationship.recipientSortOrder = index
				}
				try await relationship.update(on: database)
			}
		}
		return try await list(req: req)
	}

	func incomingRequests(req: Request) async throws -> [FriendSummaryDTO] {
		let userID = try req.auth.require(UserPayload.self).sub
		let relationships = try await Friendship.query(on: req.db)
			.filter(\.$recipient.$id == userID)
			.filter(\.$status == .pending)
			.with(\.$requester)
			.with(\.$recipient)
			.sort(\.$createdAt, .descending)
			.all()
		var summaries: [FriendSummaryDTO] = []
		for relationship in relationships {
			let summary = try await summary(for: relationship, viewerID: userID, on: req.db)
			summaries.append(summary)
		}
		return summaries
	}

	func search(req: Request) async throws -> [FriendSearchResultDTO] {
		let viewerID = try req.auth.require(UserPayload.self).sub
		let query = (req.query[String.self, at: "q"] ?? "")
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		guard (3 ... 254).contains(query.count), query.contains("@") else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Search using a school email address.", field: "q")
		}

		let users = try await User.query(on: req.db).all()
		let matches = users.filter {
			$0.id != viewerID && ($0.email?.lowercased().hasPrefix(query) ?? false)
		}
		.prefix(25)
		let userIDs = matches.compactMap(\.id)
		let relationships = try await Friendship.query(on: req.db)
			.group(.or) { group in
				group.filter(\.$requester.$id == viewerID).filter(\.$recipient.$id ~~ userIDs)
				group.filter(\.$recipient.$id == viewerID).filter(\.$requester.$id ~~ userIDs)
			}
			.all()

		return matches.compactMap { user in
			guard let userID = user.id else { return nil }
			let relationship = relationships.first {
				$0.$requester.id == userID || $0.$recipient.id == userID
			}
			return FriendSearchResultDTO(
				profile: profile(for: user),
				relationship: relationship.map { relationshipState(for: $0, viewerID: viewerID) }
			)
		}
	}

	func createRequest(req: Request) async throws -> FriendSummaryDTO {
		let requesterID = try req.auth.require(UserPayload.self).sub
		let body = try req.content.decode(CreateFriendRequest.self)
		let schoolEmail = body.schoolEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard schoolEmail.contains("@"), schoolEmail.count <= 254 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Enter a valid school email address.", field: "schoolEmail")
		}
		guard let recipient = try await User.query(on: req.db).filter(\.$email == schoolEmail).first(), let recipientID = recipient.id else {
			throw AppError(.notFound, code: .accountNotFound, reason: "No account uses that school email address.", field: "schoolEmail")
		}
		guard recipientID != requesterID else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "You cannot add yourself.", field: "schoolEmail")
		}

		if let existing = try await relationship(between: requesterID, and: recipientID, on: req.db) {
			switch existing.status {
				case .accepted:
					throw AppError(.conflict, code: .invalidRequest, reason: "You are already friends.")
				case .blocked:
					throw AppError(.forbidden, code: .invalidRequest, reason: "This friend relationship is unavailable.")
				case .pending:
					if existing.$recipient.id == requesterID {
						existing.status = .accepted
						existing.acceptedAt = .now
						try await existing.save(on: req.db)
						try await existing.$requester.load(on: req.db)
						try await existing.$recipient.load(on: req.db)
						return try await summary(for: existing, viewerID: requesterID, on: req.db)
					}
					throw AppError(.conflict, code: .invalidRequest, reason: "A friend request is already pending.")
			}
		}

		let friendship = Friendship(requesterID: requesterID, recipientID: recipientID)
		try await friendship.save(on: req.db)
		try await friendship.$requester.load(on: req.db)
		try await friendship.$recipient.load(on: req.db)
		let requester = friendship.requester
		_ = try? await NotificationService().send(
			title: "Friend request",
			body: "\(requester.displayName) sent you a friend request.",
			threadID: "friend-requests",
			collapseID: "friend-request-\(friendship.requireID().uuidString)",
			to: recipientID,
			on: req
		)
		return try await summary(for: friendship, viewerID: requesterID, on: req.db)
	}

	func profileAppearance(req: Request) async throws -> FriendProfileDTO {
		let userID = try req.auth.require(UserPayload.self).sub
		guard let user = try await User.find(userID, on: req.db) else { throw Abort(.notFound) }
		return profile(for: user)
	}

	func updateProfileAppearance(req: Request) async throws -> FriendProfileDTO {
		let userID = try req.auth.require(UserPayload.self).sub
		let body = try req.content.decode(FriendProfileAppearanceUpdateRequest.self)
		guard body.appearanceData.count <= 16 * 1024 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Profile appearance data is too large.", field: "appearanceData")
		}
		guard let user = try await User.find(userID, on: req.db) else { throw Abort(.notFound) }
		user.profileAppearanceData = body.appearanceData
		try await user.save(on: req.db)
		return profile(for: user)
	}

	func acceptRequest(req: Request) async throws -> FriendSummaryDTO {
		let recipientID = try req.auth.require(UserPayload.self).sub
		let relationshipID = try requireRelationshipID(req)
		guard let friendship = try await Friendship.query(on: req.db)
			.filter(\.$id == relationshipID)
			.filter(\.$recipient.$id == recipientID)
			.filter(\.$status == .pending)
			.with(\.$requester)
			.with(\.$recipient)
			.first()
		else { throw Abort(.notFound) }
		friendship.status = .accepted
		friendship.acceptedAt = .now
		try await friendship.save(on: req.db)
		return try await summary(for: friendship, viewerID: recipientID, on: req.db)
	}

	func detail(req: Request) async throws -> FriendDetailDTO {
		let userID = try req.auth.require(UserPayload.self).sub
		let friendID = try requireFriendID(req)
		guard let friendship = try await relationship(between: userID, and: friendID, on: req.db), friendship.status == .accepted else {
			throw Abort(.notFound)
		}
		let friend = friendship.$requester.id == userID ? friendship.$recipient.id : friendship.$requester.id
		guard let user = try await User.find(friend, on: req.db), let acceptedAt = friendship.acceptedAt else { throw Abort(.notFound) }
		return try await FriendDetailDTO(
			relationshipID: friendship.requireID(),
			friend: profile(for: user),
			acceptedAt: acceptedAt,
			timetable: timetable(for: friend, on: req.db)
		)
	}

	func removeFriend(req: Request) async throws -> HTTPStatus {
		let userID = try req.auth.require(UserPayload.self).sub
		let friendID = try requireFriendID(req)
		if let friendship = try await relationship(between: userID, and: friendID, on: req.db) {
			try await friendship.delete(on: req.db)
		}
		return .noContent
	}

	func blockFriend(req: Request) async throws -> HTTPStatus {
		let userID = try req.auth.require(UserPayload.self).sub
		let friendID = try requireFriendID(req)
		guard try await User.find(friendID, on: req.db) != nil else { throw Abort(.notFound) }
		if let friendship = try await relationship(between: userID, and: friendID, on: req.db) {
			friendship.status = .blocked
			friendship.acceptedAt = nil
			try await friendship.save(on: req.db)
		} else {
			try await Friendship(requesterID: userID, recipientID: friendID, status: .blocked).save(on: req.db)
		}
		return .noContent
	}

	private func summary(for friendship: Friendship, viewerID: UUID, on database: any Database) async throws -> FriendSummaryDTO {
		let friend = friendship.$requester.id == viewerID ? friendship.recipient : friendship.requester
		return try await FriendSummaryDTO(
			relationshipID: friendship.requireID(),
			friend: profile(for: friend),
			state: relationshipState(for: friendship, viewerID: viewerID),
			requestedAt: friendship.createdAt ?? .now,
			acceptedAt: friendship.acceptedAt,
			timetable: friendship.status == .accepted ? timetable(for: friend.requireID(), on: database) : nil
		)
	}

	private func timetable(for userID: UUID, on database: any Database) async throws -> FriendTimetableDTO? {
		guard let timetable = try await OwnerTimetable.query(on: database).filter(\.$user.$id == userID).first() else { return nil }
		let owner = try await timetable.$user.get(on: database)
		return try FriendTimetableDTO(
			title: "\(owner.displayName)'s Timetable",
			subjects: JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData),
			updatedAt: timetable.updatedAt
		)
	}

	private func profile(for user: User) -> FriendProfileDTO {
		FriendProfileDTO(userID: user.id!, displayName: user.displayName, email: user.email, appearanceData: user.profileAppearanceData)
	}

	private func relationshipState(for friendship: Friendship, viewerID: UUID?) -> FriendRelationshipState {
		switch friendship.status {
			case .accepted: .friends
			case .pending: friendship.$requester.id == viewerID ? .pendingOutgoing : .pendingIncoming
			case .blocked: .friends
		}
	}

	private func friendOrder(for friendship: Friendship, viewerID: UUID) -> Int {
		friendship.$requester.id == viewerID ? friendship.requesterSortOrder : friendship.recipientSortOrder
	}

	private func relationship(between first: UUID, and second: UUID, on database: any Database) async throws -> Friendship? {
		try await Friendship.query(on: database)
			.group(.or) { group in
				group.filter(\.$requester.$id == first).filter(\.$recipient.$id == second)
				group.filter(\.$requester.$id == second).filter(\.$recipient.$id == first)
			}
			.with(\.$requester)
			.with(\.$recipient)
			.first()
	}

	private func requireRelationshipID(_ req: Request) throws -> UUID {
		guard let raw = req.parameters.get("relationshipID"), let value = UUID(uuidString: raw) else { throw Abort(.notFound) }
		return value
	}

	private func requireFriendID(_ req: Request) throws -> UUID {
		guard let raw = req.parameters.get("friendID"), let value = UUID(uuidString: raw) else { throw Abort(.notFound) }
		return value
	}
}

private struct FriendOrderUpdateRequest: Content {
	let friendIDs: [UUID]
}
