import Vapor

struct ServerAccessModeController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let control = routes.grouped("_operations", "server-access-mode")
		control.get(use: read)
		control.put(use: update)
	}

	private func read(req: Request) async throws -> ServerAccessModeResponse {
		try requireControlToken(req)
		return ServerAccessModeResponse(
			developmentAccessOnly: try await ServerAccessModeService.developmentAccessOnly(on: req.db)
		)
	}

	private func update(req: Request) async throws -> ServerAccessModeResponse {
		try requireControlToken(req)
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

	private func requireControlToken(_ req: Request) throws {
		guard let configuredToken = Environment.get(ServerAccessModeService.controlTokenEnvironmentKey),
		      !configuredToken.isEmpty,
		      let submittedToken = req.headers.first(name: "X-PMSTT-Access-Mode-Token"),
		      submittedToken == configuredToken
		else {
			throw Abort(.notFound)
		}
	}
}

private struct ServerAccessModeUpdateRequest: Content {
	let developmentAccessOnly: Bool
}

private struct ServerAccessModeResponse: Content {
	let developmentAccessOnly: Bool
}
