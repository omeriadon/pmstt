import Fluent
import Vapor

struct SyncController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes.grouped("v1", "sync")
			.grouped(
				SessionAuthenticator(),
				UserPayload.guardMiddleware(),
				CapabilityMiddleware()
			)
		protected.post(use: synchronize)
	}

	private func synchronize(req: Request) async throws -> SyncEnvelopeResponse {
		let userID = try req.auth.require(UserPayload.self).sub
		let envelope = try req.content.decode(SyncEnvelopeRequest.self)
		guard !envelope.installationID
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.isEmpty,
			envelope.mutations.count <= 100
		else {
			throw Abort(.badRequest)
		}

		var results: [SyncMutationResult] = []
		results.reserveCapacity(envelope.mutations.count)
		for mutation in envelope.mutations {
			let result = try await result(
				for: mutation,
				userID: userID,
				on: req
			)
			results.append(result)
		}

		return SyncEnvelopeResponse(
			serverTime: .now,
			requestID: envelope.requestID,
			installationID: envelope.installationID,
			results: results,
			tombstones: [],
			nextCursor: nil
		)
	}

	private func result(
		for mutation: SyncRecordMutation,
		userID: UUID,
		on req: Request
	) async throws -> SyncMutationResult {
		try await req.db.transaction { database in
			if let receipt = try await SyncMutationReceipt.query(on: database)
				.filter(\.$user.$id == userID)
				.filter(\.$mutationID == mutation.mutationID)
				.first()
			{
				return try JSONDecoder().decode(
					SyncMutationResult.self,
					from: receipt.resultData
				)
			}

			let result = try await apply(
				mutation,
				userID: userID,
				database: database,
				logger: req.logger
			)
			let resultData = try JSONEncoder().encode(result)
			try await SyncMutationReceipt(
				userID: userID,
				mutationID: mutation.mutationID,
				resultData: resultData
			).create(on: database)
			return result
		}
	}

	private func apply(
		_ mutation: SyncRecordMutation,
		userID: UUID,
		database: any Database,
		logger: Logger
	) async throws -> SyncMutationResult {
		switch mutation.recordType {
			case .ownerTimetable:
				return try await applyOwnerTimetable(
					mutation,
					userID: userID,
					database: database,
					logger: logger
				)
		}
	}

	private func applyOwnerTimetable(
		_ mutation: SyncRecordMutation,
		userID: UUID,
		database: any Database,
		logger: Logger
	) async throws -> SyncMutationResult {
		guard mutation.operation == .upsert,
			  let payload = mutation.ownerTimetable
		else {
			return result(
				for: mutation,
				outcome: .validationRejected,
				revision: mutation.baseRevision,
				message: "The owner timetable mutation is incomplete."
			)
		}

		do {
			try validate(payload.subjects)
		} catch {
			return result(
				for: mutation,
				outcome: .validationRejected,
				revision: mutation.baseRevision,
				message: error.localizedDescription
			)
		}

		let existing = try await OwnerTimetable.query(on: database)
			.filter(\.$user.$id == userID)
			.first()
		let currentRevision = existing?.revision ?? 0
		if mutation.baseRevision != currentRevision {
			let serverRecord = try existing.map(ownerResponse)
			logger.info(
				"Record sync conflict",
				metadata: [
					"record_type": .string(mutation.recordType.rawValue),
					"mutation_id": .string(mutation.mutationID.uuidString),
					"client_revision": .string(String(mutation.baseRevision)),
					"server_revision": .string(String(currentRevision)),
				]
			)
			return SyncMutationResult(
				mutationID: mutation.mutationID,
				recordType: mutation.recordType,
				recordID: existing?.id,
				outcome: .serverRecordNewer,
				serverRevision: currentRevision,
				ownerTimetable: serverRecord,
				droppedReferenceIDs: [],
				message: "The server record is newer."
			)
		}

		let subjectsData = try JSONEncoder().encode(payload.subjects)
		let record: OwnerTimetable
		if let existing {
			existing.subjectsData = subjectsData
			existing.isSearchable = payload.isSearchable
			existing.revision += 1
			try await existing.save(on: database)
			record = existing
		} else {
			let created = OwnerTimetable(
				userID: userID,
				subjectsData: subjectsData,
				revision: 1,
				isSearchable: payload.isSearchable
			)
			try await created.save(on: database)
			record = created
		}

		return SyncMutationResult(
			mutationID: mutation.mutationID,
			recordType: mutation.recordType,
			recordID: try record.requireID(),
			outcome: .accepted,
			serverRevision: record.revision,
			ownerTimetable: try ownerResponse(record),
			droppedReferenceIDs: [],
			message: nil
		)
	}

	private func result(
		for mutation: SyncRecordMutation,
		outcome: SyncMutationOutcome,
		revision: Int,
		message: String
	) -> SyncMutationResult {
		SyncMutationResult(
			mutationID: mutation.mutationID,
			recordType: mutation.recordType,
			recordID: mutation.recordID,
			outcome: outcome,
			serverRevision: revision,
			ownerTimetable: nil,
			droppedReferenceIDs: [],
			message: message
		)
	}

	private func ownerResponse(
		_ timetable: OwnerTimetable
	) throws -> OwnerTimetableResponse {
		OwnerTimetableResponse(
			id: try timetable.requireID(),
			subjects: try JSONDecoder().decode(
				[TimetableSubjectDTO].self,
				from: timetable.subjectsData
			),
			revision: timetable.revision,
			updatedAt: timetable.updatedAt,
			isSearchable: timetable.isSearchable
		)
	}

	private func validate(_ subjects: [TimetableSubjectDTO]) throws {
		guard subjects.count <= 100 else {
			throw Abort(.badRequest, reason: "A timetable cannot contain more than 100 subjects.")
		}

		var subjectIDs = Set<String>()
		var occupiedSlots = Set<TimetableSlotDTO>()
		for subject in subjects {
			let identifier = subject.id.trimmingCharacters(
				in: .whitespacesAndNewlines
			)
			guard (1 ..< 100).contains(identifier.count),
				  (1 ..< 100).contains(subject.symbol.count),
				  subjectIDs.insert(identifier).inserted
			else {
				throw Abort(.badRequest, reason: "Timetable subjects are invalid.")
			}

			let colourComponents = [
				subject.colour.r,
				subject.colour.g,
				subject.colour.b,
				subject.colour.a,
			]
			guard colourComponents.allSatisfy({
				$0.isFinite && (0 ... 1).contains($0)
			}) else {
				throw Abort(
					.badRequest,
					reason: "Subject colours must use values between zero and one."
				)
			}

			for slot in subject.slots {
				guard (0 ... 4).contains(slot.day),
					  (0 ... 7).contains(slot.session),
					  occupiedSlots.insert(slot).inserted
				else {
					throw Abort(.badRequest, reason: "Timetable slots are invalid.")
				}
			}
		}
	}
}
