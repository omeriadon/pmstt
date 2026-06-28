import Fluent
import Vapor

struct ReportController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let passes = routes.grouped("v1", "report")
		let protected = passes.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get("user", use: reportUser)
	}

	func reportUser(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(ReportUserRequest.self)

		let reporterUserID = payload.sub

		guard let reportedUserID = UUID(uuidString: body.reportedAccountID) else {
			throw AppError(
				.badRequest,
				code: .accountNotFound,
				reason: "Unable to convert reportedUserID from string to UUID. This most likely means reportedUserID isn't a valid user ID.",
				field: "reportedUserID"
			)
		}

		guard reporterUserID != reportedUserID else {
			throw AppError(
				.badRequest,
				code: .invalidRequest,
				reason: "You cannot report yourself.",
				field: "reportedUserID"
			)
		}

		guard try await User.find(reportedUserID, on: req.db) != nil else {
			throw AppError(
				.notFound,
				code: .notFound,
				reason: "Reported user was not found.",
				field: "reportedUserID"
			)
		}

		guard try await User.find(reporterUserID, on: req.db) != nil else {
			throw Abort(.unauthorized)
		}

		return try await sendReportEmail(body: body, req: req)
	}
}
