import Fluent
import Foundation

/// Removes the accepted friendships that were incorrectly inferred from
/// historical timetable imports. Sharing a timetable is not a friendship.
struct RemoveBackfilledFriendships: AsyncMigration {
	func prepare(on database: any Database) async throws {
		let imports = try await ReceivedTimetableImport.query(on: database)
			.filter(\.$revokedAt == nil)
			.all()
		guard !imports.isEmpty else {
			return
		}

		let ownerTimetables = try await OwnerTimetable.query(on: database).all()
		let createdTimetables = try await CreatedTimetable.query(on: database).all()
		let ownerByTimetableID = Dictionary(uniqueKeysWithValues: ownerTimetables.compactMap { timetable in
			timetable.id.map { ($0, timetable.$user.id) }
		})
		let authorByTimetableID = Dictionary(uniqueKeysWithValues: createdTimetables.compactMap { timetable in
			timetable.id.map { ($0, timetable.$author.id) }
		})

		let legacyRelationshipKeys = Set(imports.compactMap { received -> LegacyFriendshipKey? in
			let ownerID: UUID? = switch received.sourceKind {
				case .accountOwner:
					ownerByTimetableID[received.timetableID]
				case .createdForThirdParty:
					authorByTimetableID[received.timetableID]
			}
			guard let ownerID, ownerID != received.$user.id else {
				return nil
			}

			return LegacyFriendshipKey(
				firstUserID: received.$user.id,
				secondUserID: ownerID,
				acceptedAt: received.importedAt
			)
		})
		guard !legacyRelationshipKeys.isEmpty else {
			return
		}

		let friendships = try await Friendship.query(on: database)
			.filter(\.$status == .accepted)
			.all()
		for friendship in friendships {
			guard let acceptedAt = friendship.acceptedAt else {
				continue
			}

			let key = LegacyFriendshipKey(
				firstUserID: friendship.$requester.id,
				secondUserID: friendship.$recipient.id,
				acceptedAt: acceptedAt
			)
			guard legacyRelationshipKeys.contains(key) else {
				continue
			}

			try await friendship.delete(on: database)
		}
	}

	func revert(on _: any Database) async throws {}
}

private struct LegacyFriendshipKey: Hashable {
	let firstUserID: UUID
	let secondUserID: UUID
	let acceptedAt: Date

	init(firstUserID: UUID, secondUserID: UUID, acceptedAt: Date) {
		if firstUserID.uuidString < secondUserID.uuidString {
			self.firstUserID = firstUserID
			self.secondUserID = secondUserID
		} else {
			self.firstUserID = secondUserID
			self.secondUserID = firstUserID
		}
		self.acceptedAt = acceptedAt
	}
}
