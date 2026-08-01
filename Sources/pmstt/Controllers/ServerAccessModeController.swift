import Vapor

struct ServerAccessModeController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let control = routes
			.grouped("_operations", "server-access-mode")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware())
		control.get(use: read)
		control.put(use: update)
	}

	private func read(req: Request) async throws -> ServerAccessModeResponse {
		try await requireSystemOwner(req)
		return try await ServerAccessModeResponse(
			developmentAccessOnly: ServerAccessModeService.developmentAccessOnly(on: req.db)
		)
	}

	private func update(req: Request) async throws -> ServerAccessModeResponse {
		try await requireSystemOwner(req)
		let request = try req.content.decode(ServerAccessModeUpdateRequest.self)
		let mode = try await ServerAccessModeService.update(
			developmentAccessOnly: request.developmentAccessOnly,
			on: req.db
		)

		req.logger.warning(
			"Updated server access mode",
			metadata: [
				"development_access_only": .stringConvertible(mode.developmentAccessOnly),
			]
		)

		return ServerAccessModeResponse(
			developmentAccessOnly: mode.developmentAccessOnly
		)
	}

	private func requireSystemOwner(_ req: Request) async throws {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db),
		      user.resolvedAccountAuthority == .systemOwner
		else {
			throw Abort(.forbidden)
		}
	}
}

private struct ServerAccessModeUpdateRequest: Content {
	let developmentAccessOnly: Bool
}

private struct ServerAccessModeResponse: Content {
	let developmentAccessOnly: Bool
}
