import Fluent
import Vapor

struct AboutController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes.grouped("v1")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware())
		protected.get("about", use: about)

		let admin = routes.grouped("v1", "administration")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		admin.get("about-contributors", use: contributors)
		admin.post("about-contributors", use: createContributor)
		admin.put("about-contributors", ":contributorID", use: updateContributor)
		admin.delete("about-contributors", ":contributorID", use: deleteContributor)
		admin.put("about-contributors", "order", use: reorderContributors)
	}

	private func about(req: Request) async throws -> [AboutContributorResponse] {
		try await contributors(on: req.db)
	}

	private func contributors(req: Request) async throws -> [AboutContributorResponse] {
		_ = try await requireSystemOwner(req)
		return try await contributors(on: req.db)
	}

	private func contributors(on database: any Database) async throws -> [AboutContributorResponse] {
		try await AboutContributor.query(on: database)
			.sort(\.$sortOrder)
			.all()
			.compactMap(AboutContributorResponse.init)
	}

	private func createContributor(req: Request) async throws -> [AboutContributorResponse] {
		_ = try await requireSystemOwner(req)
		let request = try req.content.decode(AboutContributorRequest.self)
		try validate(request)
		let lastOrder = try await AboutContributor.query(on: req.db)
			.sort(\.$sortOrder, .descending)
			.first()?.sortOrder ?? -1
		try await AboutContributor(
			name: request.name.trimmingCharacters(in: .whitespacesAndNewlines),
			role: request.role.trimmingCharacters(in: .whitespacesAndNewlines),
			sortOrder: lastOrder + 1
		).create(on: req.db)
		return try await contributors(on: req.db)
	}

	private func updateContributor(req: Request) async throws -> [AboutContributorResponse] {
		_ = try await requireSystemOwner(req)
		let contributor = try await contributor(req: req)
		let request = try req.content.decode(AboutContributorRequest.self)
		try validate(request)
		contributor.name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
		contributor.role = request.role.trimmingCharacters(in: .whitespacesAndNewlines)
		try await contributor.update(on: req.db)
		return try await contributors(on: req.db)
	}

	private func deleteContributor(req: Request) async throws -> [AboutContributorResponse] {
		_ = try await requireSystemOwner(req)
		try await contributor(req: req).delete(on: req.db)
		return try await contributors(on: req.db)
	}

	private func reorderContributors(req: Request) async throws -> [AboutContributorResponse] {
		_ = try await requireSystemOwner(req)
		let request = try req.content.decode(AboutContributorOrderRequest.self)
		guard Set(request.contributorIDs).count == request.contributorIDs.count else {
			throw Abort(.badRequest, reason: "Contributor IDs must be unique.")
		}
		let existing = try await AboutContributor.query(on: req.db).all()
		let byID = Dictionary(uniqueKeysWithValues: existing.compactMap { contributor in
			contributor.id.map { ($0, contributor) }
		})
		guard Set(byID.keys) == Set(request.contributorIDs) else {
			throw Abort(.badRequest, reason: "Contributor IDs do not match the current list.")
		}
		try await req.db.transaction { database in
			for (index, id) in request.contributorIDs.enumerated() {
				guard let contributor = byID[id] else {
					throw Abort(.badRequest)
				}
				contributor.sortOrder = index
				try await contributor.update(on: database)
			}
		}
		return try await contributors(on: req.db)
	}

	private func contributor(req: Request) async throws -> AboutContributor {
		guard let id = req.parameters.get("contributorID", as: UUID.self),
		      let contributor = try await AboutContributor.find(id, on: req.db)
		else {
			throw Abort(.notFound)
		}
		return contributor
	}

	private func requireSystemOwner(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound)
		}
		guard user.resolvedAccountAuthority == .systemOwner else {
			throw Abort(.forbidden)
		}
		return user
	}

	private func validate(_ request: AboutContributorRequest) throws {
		let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
		let role = request.role.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty, name.count <= 120, !role.isEmpty, role.count <= 180 else {
			throw Abort(.badRequest, reason: "Contributor name and role are required.")
		}
	}
}

private struct AboutContributorRequest: Content {
	let name: String
	let role: String
}

private struct AboutContributorOrderRequest: Content {
	let contributorIDs: [UUID]
}

struct AboutContributorResponse: Content, Identifiable {
	let id: UUID
	let name: String
	let role: String
	let sortOrder: Int

	init?(_ contributor: AboutContributor) {
		guard let id = contributor.id else { return nil }
		self.id = id
		name = contributor.name
		role = contributor.role
		sortOrder = contributor.sortOrder
	}
}
