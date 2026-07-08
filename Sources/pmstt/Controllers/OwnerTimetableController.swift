import Fluent
import Vapor

struct OwnerTimetableController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let timetable = routes.grouped("v1", "timetables", "owner")
		let protected = timetable.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get(use: getOwnerTimetable)
		protected.put(use: updateOwnerTimetable)
		protected.put("visibility", use: updateVisibility)
	}

	func updateVisibility(req: Request) async throws -> OwnerTimetableResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(OwnerTimetableVisibilityUpdateRequest.self)

		let timetable: OwnerTimetable
		if let existing = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.first()
		{
			existing.isSearchable = body.isSearchable
			existing.revision += 1
			try await existing.save(on: req.db)
			timetable = existing
		} else {
			timetable = try OwnerTimetable(
				userID: payload.sub,
				subjectsData: JSONEncoder().encode([TimetableSubjectDTO]()),
				revision: 1,
				isSearchable: body.isSearchable
			)
			try await timetable.save(on: req.db)
		}

		return try response(for: timetable)
	}

	func getOwnerTimetable(req: Request) async throws -> OwnerTimetableResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let timetable = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.first()
		else {
			return OwnerTimetableResponse(subjects: [], revision: 0, updatedAt: nil, isSearchable: true)
		}

		return try response(for: timetable)
	}

	func updateOwnerTimetable(req: Request) async throws -> OwnerTimetableResponse {
		let payload = try req.auth.require(UserPayload.self)
		req.logger.info("Owner timetable update started", metadata: ["user_id": .string(payload.sub.uuidString)])
		let body = try req.content.decode(OwnerTimetableUpdateRequest.self)
		req.logger.info("Owner timetable update decoded", metadata: ["subject_count": .stringConvertible(body.subjects.count)])
		try validate(body.subjects)
		let subjectsData = try JSONEncoder().encode(body.subjects)

		let timetable: OwnerTimetable
		if let existing = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.first()
		{
			req.logger.info("Owner timetable update found existing row", metadata: ["revision": .stringConvertible(existing.revision)])
			if let expectedRevision = body.expectedRevision,
			   expectedRevision != existing.revision
			{
				throw AppError(
					.conflict,
					code: .timetableConflict,
					reason: "The timetable changed on another device. Refresh and try again."
				)
			}

			existing.subjectsData = subjectsData
			existing.isSearchable = body.isSearchable ?? existing.isSearchable
			existing.revision += 1
			try await existing.save(on: req.db)
			req.logger.info("Owner timetable update saved existing row", metadata: ["revision": .stringConvertible(existing.revision)])
			timetable = existing
		} else {
			req.logger.info("Owner timetable update creating row")
			if let expectedRevision = body.expectedRevision, expectedRevision != 0 {
				throw AppError(
					.conflict,
					code: .timetableConflict,
					reason: "The timetable changed on another device. Refresh and try again."
				)
			}

			timetable = OwnerTimetable(
				userID: payload.sub,
				subjectsData: subjectsData,
				revision: 1,
				isSearchable: body.isSearchable ?? true
			)
			try await timetable.save(on: req.db)
			req.logger.info("Owner timetable update saved new row")
		}

		return try response(for: timetable)
	}

	private func response(for timetable: OwnerTimetable) throws -> OwnerTimetableResponse {
		let subjects: [TimetableSubjectDTO]
		do {
			subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData)
		} catch {
			throw AppError(
				.internalServerError,
				code: .internalServerError,
				reason: "Stored timetable data is invalid."
			)
		}

		return OwnerTimetableResponse(
			subjects: subjects,
			revision: timetable.revision,
			updatedAt: timetable.updatedAt,
			isSearchable: timetable.isSearchable
		)
	}

	private func validate(_ subjects: [TimetableSubjectDTO]) throws {
		guard subjects.count <= 100 else {
			throw invalidTimetable("A timetable cannot contain more than 100 subjects.")
		}

		var subjectIDs = Set<String>()
		var occupiedSlots = Set<TimetableSlotDTO>()

		for subject in subjects {
			let trimmedID = subject.id.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmedID.isEmpty, trimmedID.count <= 100, subject.symbol.count <= 20 else {
				throw invalidTimetable("Subject names and symbols must be valid.")
			}
			guard subjectIDs.insert(trimmedID).inserted else {
				throw invalidTimetable("Subject names must be unique.")
			}

			let components = [subject.colour.r, subject.colour.g, subject.colour.b, subject.colour.a]
			guard components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
				throw invalidTimetable("Subject colours must use values between zero and one.")
			}

			for slot in subject.slots {
				guard (0 ... 4).contains(slot.day), (0 ... 7).contains(slot.session) else {
					throw invalidTimetable("Timetable slots are outside the supported school week.")
				}
				guard occupiedSlots.insert(slot).inserted else {
					throw invalidTimetable("A timetable slot can only contain one subject.")
				}
			}
		}
	}

	private func invalidTimetable(_ reason: String) -> AppError {
		AppError(.badRequest, code: .invalidTimetable, reason: reason, field: "subjects")
	}
}
