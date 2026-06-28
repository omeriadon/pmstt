import Fluent
import Vapor

struct ReceivedTimetableController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let received = routes.grouped("v1", "timetables", "received")
		let protected = received.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get(use: getProjection)
		protected.put(use: replaceProjection)
	}

	func getProjection(req: Request) async throws -> [ReceivedPassMirrorDTO] {
		let payload = try req.auth.require(UserPayload.self)
		let records = try await ReceivedPassMirror.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.sort(\.$receivedAt, .ascending)
			.all()
		return try records.map(response)
	}

	func replaceProjection(req: Request) async throws -> [ReceivedPassMirrorDTO] {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(ReceivedProjectionUpdateRequest.self)
		try validate(body)

		let records = try await req.db.transaction { database in
			try await ReceivedPassMirror.query(on: database)
				.filter(\.$user.$id == payload.sub)
				.delete()

			var created: [ReceivedPassMirror] = []
			created.reserveCapacity(body.timetables.count)

			for timetable in body.timetables where !timetable.isDeleted {
				let record = try ReceivedPassMirror(
					userID: payload.sub,
					passSerialNumber: timetable.id,
					issuerAccountID: timetable.issuerAccountID,
					sourceKind: timetable.sourceKind,
					signedDisplayName: timetable.signedDisplayName,
					authorDisplayName: timetable.authorDisplayName,
					subjectsData: JSONEncoder().encode(timetable.subjects),
					isDeleted: false,
					walletRevision: body.walletRevision,
					receivedAt: timetable.receivedAt,
					passUpdatedAt: timetable.passUpdatedAt
				)
				try await record.save(on: database)
				created.append(record)
			}

			return created
		}

		return try records.map(response)
	}

	private func response(_ record: ReceivedPassMirror) throws -> ReceivedPassMirrorDTO {
		let subjects: [TimetableSubjectDTO]
		do {
			subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: record.subjectsData)
		} catch {
			throw AppError(
				.internalServerError,
				code: .internalServerError,
				reason: "Stored received timetable data is invalid."
			)
		}

		return ReceivedPassMirrorDTO(
			id: record.passSerialNumber,
			issuerAccountID: record.issuerAccountID,
			sourceKind: record.sourceKind,
			signedDisplayName: record.signedDisplayName,
			authorDisplayName: record.authorDisplayName,
			subjects: subjects,
			receivedAt: record.receivedAt,
			passUpdatedAt: record.passUpdatedAt,
			isDeleted: record.isDeleted,
			walletRevision: record.walletRevision
		)
	}

	private func validate(_ request: ReceivedProjectionUpdateRequest) throws {
		guard request.walletRevision >= 0, request.timetables.count <= 250 else {
			throw invalidProjection("The received timetable projection is too large or has an invalid revision.")
		}

		var serialNumbers = Set<String>()
		for timetable in request.timetables {
			let serialNumber = timetable.id.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !serialNumber.isEmpty, serialNumber.count <= 200 else {
				throw invalidProjection("Every received timetable requires a valid pass serial number.")
			}
			guard serialNumbers.insert(serialNumber).inserted else {
				throw invalidProjection("Pass serial numbers must be unique.")
			}
			guard ["accountOwner", "authoredForThirdParty"].contains(timetable.sourceKind) else {
				throw invalidProjection("A received timetable has an invalid source kind.")
			}
			guard !timetable.signedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
				throw invalidProjection("A received timetable has no signed display name.")
			}
		}
	}

	private func invalidProjection(_ reason: String) -> AppError {
		AppError(.badRequest, code: .invalidTimetable, reason: reason, field: "timetables")
	}
}
