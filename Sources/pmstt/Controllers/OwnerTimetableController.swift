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

		try await updateWalletPass(for: payload.sub, revision: timetable.revision, req: req)
		return try response(for: timetable)
	}

	func getOwnerTimetable(req: Request) async throws -> OwnerTimetableResponse {
		let payload = try req.auth.require(UserPayload.self)

		guard let timetable = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.first()
		else {
			return OwnerTimetableResponse(
				subjects: [],
				revision: 0,
				updatedAt: nil,
				isSearchable: true
			)
		}

		return try response(for: timetable)
	}

	func updateOwnerTimetable(req: Request) async throws -> OwnerTimetableResponse {
		let payload = try req.auth.require(UserPayload.self)

		logInfo(
			req,
			"Owner timetable update entered controller",
			[
				"user_id": payload.sub.uuidString,
				"request_id": req.requestID,
				"content_length": req.headers.first(name: "Content-Length") ?? "missing",
				"content_type": req.headers.contentType?.serialize() ?? "missing",
			]
		)

		let body: OwnerTimetableUpdateRequest

		do {
			body = try req.content.decode(OwnerTimetableUpdateRequest.self)
		} catch {
			logError(
				req,
				"Owner timetable update body decode failed",
				[
					"request_id": req.requestID,
					"error": String(describing: error),
				]
			)

			throw error
		}

		logInfo(
			req,
			"Owner timetable update decoded",
			[
				"request_id": req.requestID,
				"subject_count": String(body.subjects.count),
				"expected_revision": body.expectedRevision.map(String.init) ?? "nil",
				"is_searchable": body.isSearchable.map(String.init) ?? "nil",
			]
		)

		try validate(body.subjects)

		logInfo(
			req,
			"Owner timetable update validated",
			[
				"request_id": req.requestID,
			]
		)

		let subjectsData = try JSONEncoder().encode(body.subjects)

		logInfo(
			req,
			"Owner timetable update encoded storage blob",
			[
				"request_id": req.requestID,
				"stored_bytes": String(subjectsData.count),
			]
		)

		logInfo(
			req,
			"Owner timetable update querying existing row",
			[
				"request_id": req.requestID,
			]
		)

		let timetable: OwnerTimetable

		if let existing = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.first()
		{
			logInfo(
				req,
				"Owner timetable update found existing row",
				[
					"request_id": req.requestID,
					"revision": String(existing.revision),
				]
			)

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

			logInfo(
				req,
				"Owner timetable update saving existing row",
				[
					"request_id": req.requestID,
					"next_revision": String(existing.revision),
				]
			)

			try await existing.save(on: req.db)

			logInfo(
				req,
				"Owner timetable update saved existing row",
				[
					"request_id": req.requestID,
					"revision": String(existing.revision),
				]
			)

			timetable = existing
		} else {
			logInfo(
				req,
				"Owner timetable update creating row",
				[
					"request_id": req.requestID,
				]
			)

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

			logInfo(
				req,
				"Owner timetable update saving new row",
				[
					"request_id": req.requestID,
				]
			)

			try await timetable.save(on: req.db)

			logInfo(
				req,
				"Owner timetable update saved new row",
				[
					"request_id": req.requestID,
				]
			)
		}

		try await updateWalletPass(for: payload.sub, revision: timetable.revision, req: req)

		logInfo(
			req,
			"Owner timetable update returning response",
			[
				"request_id": req.requestID,
				"revision": String(timetable.revision),
			]
		)

		return try response(for: timetable)
	}

	private func updateWalletPass(for userID: UUID, revision: Int, req: Request) async throws {
		guard let user = try await User.find(userID, on: req.db),
		      let record = try await PassRecord.query(on: req.db)
		      .filter(\.$serialNumber == user.selfPassSerialNumber)
		      .first()
		else {
			return
		}

		record.revision = revision
		record.isDeleted = false
		try await record.save(on: req.db)
		try? await WalletPushService.sendUpdate(for: record.serialNumber, req: req)
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

			guard (1 ..< 100).contains(trimmedID.count),
			      (1 ..< 100).contains(subject.symbol.count)
			else {
				throw invalidTimetable("Subject names and symbols must be valid.")
			}

			guard subjectIDs.insert(trimmedID).inserted else {
				throw invalidTimetable("Subject names must be unique.")
			}

			let components = [
				subject.colour.r,
				subject.colour.g,
				subject.colour.b,
				subject.colour.a,
			]

			guard components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
				throw invalidTimetable("Subject colours must use values between zero and one.")
			}

			for slot in subject.slots {
				guard (0 ... 4).contains(slot.day),
				      (0 ... 7).contains(slot.session)
				else {
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

	private func logInfo(
		_ req: Request,
		_ message: String,
		_ values: [String: String] = [:]
	) {
		req.logger.info(
			.init(stringLiteral: message),
			metadata: metadata(values)
		)
	}

	private func logError(
		_ req: Request,
		_ message: String,
		_ values: [String: String] = [:]
	) {
		req.logger.error(
			.init(stringLiteral: message),
			metadata: metadata(values)
		)
	}

	private func metadata(_ values: [String: String]) -> Logger.Metadata {
		var metadata: Logger.Metadata = [:]

		for (key, value) in values {
			metadata[key] = .string(value)
		}

		return metadata
	}
}
