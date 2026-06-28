import Fluent
import Vapor

struct ReportController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let report = routes.grouped("v1", "report")
		let protected = report.grouped(
			UserPayload.authenticator(),
			UserPayload.guardMiddleware()
		)

		protected.post("user", use: reportUser)
	}

	func reportUser(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(ReportUserRequest.self)

		let reporterUserID = payload.sub

		guard let reportedUserID = UUID(uuidString: body.reportedAccountID) else {
			throw AppError(
				.badRequest,
				code: .invalidRequest,
				reason: "reportedAccountID is not a valid UUID.",
				field: "reportedAccountID"
			)
		}

		guard reporterUserID != reportedUserID else {
			throw AppError(
				.badRequest,
				code: .invalidRequest,
				reason: "You cannot report yourself.",
				field: "reportedAccountID"
			)
		}

		guard let reporterUser = try await User.find(reporterUserID, on: req.db) else {
			throw Abort(.unauthorized)
		}

		guard let reportedUser = try await User.find(reportedUserID, on: req.db) else {
			throw AppError(
				.notFound,
				code: .accountNotFound,
				reason: "Reported user was not found.",
				field: "reportedAccountID"
			)
		}

		return try await sendReportEmail(
			body: body,
			reporterUser: reporterUser,
			reportedUser: reportedUser,
			req: req
		)
	}
}
