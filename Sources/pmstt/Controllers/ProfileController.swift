import Fluent
import Vapor

struct ProfileController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let profile = routes.grouped("v1", "profile")
		let protected = profile.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get(use: getProfile)
		protected.put(use: updateProfile)
		protected.delete(use: deleteAccount)
	}

	func getProfile(req: Request) async throws -> UserProfileResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound, reason: "User not found.")
		}

		return UserProfileResponse(
			id: try user.requireID(),
			email: user.email,
			displayName: user.displayName,
			createdAt: user.createdAt
		)
	}

	func updateProfile(req: Request) async throws -> UserProfileResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(UpdateProfileRequest.self)

		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound, reason: "User not found.")
		}

		if let displayName = body.displayName {
			user.displayName = displayName.isEmpty ? nil : displayName
		}

		if let email = body.email {
			guard !email.isEmpty, email.contains("@") else {
				throw Abort(.badRequest, reason: "Invalid email format.")
			}
			let normalizedEmail = email.lowercased()
			if normalizedEmail != user.email {
				let existing = try await User.query(on: req.db)
					.filter(\.$email == normalizedEmail)
					.first()
				if existing != nil {
					throw Abort(.conflict, reason: "Email is already registered.")
				}
				user.email = normalizedEmail
			}
		}

		try await user.save(on: req.db)

		return UserProfileResponse(
			id: try user.requireID(),
			email: user.email,
			displayName: user.displayName,
			createdAt: user.createdAt
		)
	}

	func deleteAccount(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound, reason: "User not found.")
		}

		try await user.delete(on: req.db)
		return .noContent
	}
}
