import Fluent
import FuzzyMatchingSwift
import Vapor

struct TimetableDiscoveryController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let routes = routes.grouped("v1", "timetables")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		routes.get("search", use: search)
		routes.get(":timetableID", use: detail)
		routes.get(":timetableID", "pass", use: pass)
	}

	func search(req: Request) async throws -> [TimetableSearchResult] {
		_ = try req.auth.require(UserPayload.self)
		let query = (req.query[String.self, at: "q"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		guard (1 ..< 50).contains(query.count) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Search queries must be under 49 characters.", field: "q")
		}

		let owners = try await OwnerTimetable.query(on: req.db)
			.filter(\.$isSearchable == true)
			.with(\.$user)
			.all()
		let authored = try await AuthoredTimetable.query(on: req.db)
			.filter(\.$isSearchable == true)
			.with(\.$author)
			.all()

		let maxConfidence = 0.5

		var results: [TimetableSearchResult] = []
		for timetable in owners {
			guard let id = timetable.id, let authorID = timetable.user.id else { continue }
			let title = "\(timetable.user.displayName)'s Timetable"

			guard let confidence = bestConfidence(
				query: query,
				title: title,
				author: timetable.user.displayName
			),
				confidence <= maxConfidence
			else { continue }

			results.append(
				.init(
					id: id,
					title: title,
					authorAccountID: authorID,
					authorDisplayName: timetable.user.displayName,
					sourceKind: .accountOwner,
					confidence: confidence
				)
			)
		}
		for timetable in authored {
			guard let id = timetable.id, let authorID = timetable.author.id else { continue }

			guard let confidence = bestConfidence(
				query: query,
				title: timetable.subjectDisplayName,
				author: timetable.author.displayName
			),
				confidence <= maxConfidence
			else { continue }

			results.append(
				.init(id: id,
				      title: timetable.subjectDisplayName,
				      authorAccountID: authorID,
				      authorDisplayName: timetable.author.displayName,
				      sourceKind: .authoredForThirdParty,
				      confidence: confidence)
			)
		}

		let sortedResults = results.sorted {
			if $0.confidence == $1.confidence {
				return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
			}
			return $0.confidence < $1.confidence
		}

		return Array(sortedResults.prefix(50))
	}

	func detail(req: Request) async throws -> TimetableDetailResponse {
		let payload = try req.auth.require(UserPayload.self)
		let resolved = try await TimetableResolver.resolve(req: req, userID: payload.sub)
		return try await resolved.detail(on: req.db, viewerID: payload.sub)
	}

	func pass(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)
		let resolved = try await TimetableResolver.resolve(req: req, userID: payload.sub)
		return try await PassFactory.response(for: resolved, req: req)
	}

	private func bestConfidence(query: String, title: String, author: String) -> Double? {
		[title.confidenceScore(query), author.confidenceScore(query)].compactMap(\.self).min()
	}
}

enum ResolvedTimetable {
	case owner(OwnerTimetable)
	case authored(AuthoredTimetable)

	var id: UUID {
		get throws { try modelID() }
	}

	var title: String {
		switch self { case let .owner(value): "\(value.user.displayName)'s Timetable"; case let .authored(value): value.subjectDisplayName }
	}

	var author: User {
		switch self { case let .owner(value): value.user; case let .authored(value): value.author }
	}

	var sourceKind: SourceKind {
		switch self { case .owner: .accountOwner; case .authored: .authoredForThirdParty }
	}

	var subjectsData: Data {
		switch self { case let .owner(value): value.subjectsData; case let .authored(value): value.subjectsData }
	}

	var revision: Int {
		switch self { case let .owner(value): value.revision; case let .authored(value): value.revision }
	}

	var isSearchable: Bool {
		switch self { case let .owner(value): value.isSearchable; case let .authored(value): value.isSearchable }
	}

	var updatedAt: Date? {
		switch self { case let .owner(value): value.updatedAt; case let .authored(value): value.updatedAt }
	}

	var serialNumber: String {
		get throws { switch self { case let .owner(value): return value.user.selfPassSerialNumber; case let .authored(value): return value.passSerialNumber } }
	}

	func detail(on database: any Database, viewerID: UUID) async throws -> TimetableDetailResponse {
		let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: subjectsData)
		let serial = try serialNumber
		let installs = try await PassRegistration.query(on: database).filter(\.$serialNumber == serial).count()
		let authorID = try author.requireID()
		return try .init(id: id, title: title, authorAccountID: authorID, authorDisplayName: author.displayName, sourceKind: sourceKind, subjects: subjects, subjectCount: subjects.count, weeklyLessonCount: subjects.reduce(0) { $0 + $1.slots.count }, updatedAt: updatedAt, activeInstallCount: installs, isSearchable: isSearchable, canEdit: viewerID == authorID)
	}

	private func modelID() throws -> UUID {
		switch self { case let .owner(value): try value.requireID(); case let .authored(value): try value.requireID() }
	}
}

enum TimetableResolver {
	static func resolve(req: Request, userID: UUID) async throws -> ResolvedTimetable {
		guard let idString = req.parameters.get("timetableID"), let id = UUID(uuidString: idString) else { throw Abort(.notFound) }
		switch try await AuthoritativeTimetableResolver.resolveForViewer(id: id, userID: userID, on: req.db) {
		case .available(let source):
			switch source { case .owner(let owner): return .owner(owner); case .authored(let authored): return .authored(authored) }
		case .privateSource, .missing, .ambiguous: throw Abort(.notFound)
		}
	}
}
