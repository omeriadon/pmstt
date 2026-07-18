import Fluent
import Foundation

struct BackfillReceivedTimetableImports: AsyncMigration {
	private let batchSize = 250

	func prepare(on database: any Database) async throws {
		var offset = 0
		var totalInserted = 0
		var totalSkipped = 0
		while true {
			let batchOffset = offset
			let batch = try await database.transaction { database -> (processed: Int, inserted: Int, skipped: Int) in
				let mirrors = try await ReceivedPassMirror.query(on: database)
					.filter(\.$isDeleted == false)
					.sort(\.$id, .ascending)
					.range(batchOffset ..< (batchOffset + batchSize))
					.all()
				guard !mirrors.isEmpty else { return (0, 0, 0) }

				let issuerIDs = Set(mirrors.compactMap { UUID(uuidString: $0.issuerAccountID) })
				let serials = Set(mirrors.map(\.passSerialNumber))
				let owners = issuerIDs.isEmpty ? [] : try await OwnerTimetable.query(on: database).filter(\.$user.$id ~~ issuerIDs).with(\.$user).all()
				let authored = serials.isEmpty ? [] : try await AuthoredTimetable.query(on: database).filter(\.$passSerialNumber ~~ serials).all()
				let ownerByIdentity: [String: UUID] = Dictionary(uniqueKeysWithValues: owners.compactMap { owner in
					guard let id = owner.id else { return nil }
					return ("\(owner.$user.id.uuidString):\(owner.user.selfPassSerialNumber)", id)
				})
				let authoredBySerial: [String: UUID] = Dictionary(uniqueKeysWithValues: authored.compactMap { value in value.id.map { (value.passSerialNumber, $0) } })
				let userIDs = Set(mirrors.map(\.$user.id))
				let existing = try await ReceivedTimetableImport.query(on: database).filter(\.$user.$id ~~ userIDs).all()
				var existingKeys = Set(existing.map { "\($0.$user.id.uuidString):\($0.timetableID.uuidString):\($0.sourceKind.rawValue)" })
				var inserted = 0
				var skipped = 0
				for mirror in mirrors {
					let sourceID: UUID?
					switch mirror.sourceKind {
						case .accountOwner:
							let issuer = UUID(uuidString: mirror.issuerAccountID)?.uuidString ?? ""
							sourceID = ownerByIdentity["\(issuer):\(mirror.passSerialNumber)"]
						case .authoredForThirdParty:
							sourceID = authoredBySerial[mirror.passSerialNumber]
					}
					guard let sourceID else { skipped += 1; continue }
					let key = "\(mirror.$user.id.uuidString):\(sourceID.uuidString):\(mirror.sourceKind.rawValue)"
					guard !existingKeys.contains(key) else { continue }
					try await ReceivedTimetableImport(userID: mirror.$user.id, timetableID: sourceID, sourceKind: mirror.sourceKind, importedAt: mirror.receivedAt).save(on: database)
					existingKeys.insert(key)
					inserted += 1
				}
				return (mirrors.count, inserted, skipped)
			}
			totalInserted += batch.inserted
			totalSkipped += batch.skipped
			print("BackfillReceivedTimetableImports batch offset=\(offset) processed=\(batch.processed) inserted=\(batch.inserted) skipped=\(batch.skipped)")
			guard batch.processed == batchSize else { break }
			offset += batch.processed
		}
		print("BackfillReceivedTimetableImports inserted=\(totalInserted) skipped=\(totalSkipped)")
	}

	func revert(on _: any Database) async throws {}
}
