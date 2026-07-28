import Fluent

/// Preserves alpha-era received timetable relationships as accepted friendships.
struct BackfillFriendshipsFromReceivedTimetables: AsyncMigration {
	func prepare(on database: any Database) async throws {
		let imports = try await ReceivedTimetableImport.query(on: database)
			.filter(\.$revokedAt == nil)
			.all()
		guard !imports.isEmpty else { return }

		let ownerTimetables = try await OwnerTimetable.query(on: database).all()
		let createdTimetables = try await CreatedTimetable.query(on: database).all()
		let ownerByTimetableID = Dictionary(uniqueKeysWithValues: ownerTimetables.compactMap { timetable in
			timetable.id.map { ($0, timetable.$user.id) }
		})
		let authorByTimetableID = Dictionary(uniqueKeysWithValues: createdTimetables.compactMap { timetable in
			timetable.id.map { ($0, timetable.$author.id) }
		})

		var relationshipKeys = try await Set(
			Friendship.query(on: database).all().map {
				canonicalKey($0.$requester.id, $0.$recipient.id)
			}
		)

		for received in imports {
			let ownerID: UUID? = switch received.sourceKind {
				case .accountOwner:
					ownerByTimetableID[received.timetableID]
				case .createdForThirdParty:
					authorByTimetableID[received.timetableID]
			}
			guard let ownerID, ownerID != received.$user.id else { continue }
			let key = canonicalKey(received.$user.id, ownerID)
			guard relationshipKeys.insert(key).inserted else { continue }
			try await Friendship(
				requesterID: received.$user.id,
				recipientID: ownerID,
				status: .accepted,
				acceptedAt: received.importedAt
			).save(on: database)
		}
	}

	func revert(on _: any Database) async throws {}

	private func canonicalKey(_ first: UUID, _ second: UUID) -> String {
		[first.uuidString, second.uuidString].sorted().joined(separator: ":")
	}
}
