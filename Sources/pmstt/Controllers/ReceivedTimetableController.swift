import Fluent
import Vapor

struct ReceivedTimetableController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let received = routes.grouped("v1", "timetables", "received")
		let protected = received.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get(use: getReceivedTimetables)
		protected.put(use: replaceReceivedTimetables)
		protected.delete(":serialNumber", use: deleteReceivedTimetable)
	}

	func getReceivedTimetables(req: Request) async throws -> [ReceivedPassMirrorDTO] {
		let payload = try req.auth.require(UserPayload.self)
		let records = try await ReceivedPassMirror.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.sort(\.$receivedAt, .ascending)
			.all()
		return try records.map(response)
	}

	func replaceReceivedTimetables(req: Request) async throws -> [ReceivedPassMirrorDTO] {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(ReceivedProjectionUpdateRequest.self)
		try validate(body)

		try await req.db.transaction { database in
			let submittedSerialNumbers = Set(body.timetables.lazy.filter { !$0.isDeleted }.map(\.id))
			let existingRecords = try await ReceivedPassMirror.query(on: database)
				.filter(\.$user.$id == payload.sub)
				.all()

			for record in existingRecords where !submittedSerialNumbers.contains(record.passSerialNumber) {
				try await record.delete(on: database)
			}

			for timetable in body.timetables {
				guard !timetable.isDeleted else {
					continue
				}

				if let existing = try await ReceivedPassMirror.query(on: database)
					.filter(\.$user.$id == payload.sub)
					.filter(\.$passSerialNumber == timetable.id)
					.first()
				{
					existing.issuerAccountID = timetable.issuerAccountID
					existing.sourceKind = timetable.sourceKind
					existing.signedDisplayName = timetable.signedDisplayName
					existing.authorDisplayName = timetable.authorDisplayName
					existing.subjectsData = try JSONEncoder().encode(timetable.subjects)
					existing.isDeleted = false
					existing.walletRevision = body.walletRevision
					existing.receivedAt = timetable.receivedAt
					existing.passUpdatedAt = timetable.passUpdatedAt

					try await existing.save(on: database)
				} else {
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
				}
			}
		}

		let records = try await ReceivedPassMirror.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.sort(\.$receivedAt, .ascending)
			.all()

		return try records.map(response)
	}

	func deleteReceivedTimetable(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let serialNumber = try req.parameters.require("serialNumber")

		try await ReceivedPassMirror.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$passSerialNumber == serialNumber)
			.delete()

		return .noContent
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
			guard !timetable.signedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
				throw invalidProjection("A received timetable has no signed display name.")
			}
		}
	}

	private func invalidProjection(_ reason: String) -> AppError {
		AppError(.badRequest, code: .invalidTimetable, reason: reason, field: "timetables")
	}
}
