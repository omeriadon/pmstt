import Vapor

struct SchoolWeatherController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes.grouped("v1", "weather")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		protected.get(use: current)
	}

	private func current(req: Request) async throws -> SchoolWeatherResponse {
		try await SchoolWeatherService().current(on: req)
	}
}
