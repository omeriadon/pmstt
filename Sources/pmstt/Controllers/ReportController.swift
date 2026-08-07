import Fluent
import Vapor

struct ReportController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let report = routes.grouped("v1", "report")
		let protected = report.grouped(
			SessionAuthenticator(),
			UserPayload.guardMiddleware(),
			CapabilityMiddleware()
		)

		protected.post("user", use: reportUser)
		protected.post("feedback", use: reportFeedback)
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
		let report = UserReport(reporterID: reporterUserID, reportedUserID: reportedUserID)
		try await report.create(on: req.db)
		try await sendModerationNotification(
			title: "User report",
			body: "\(reporterUser.displayName) reported \(reportedUser.displayName).",
			collapseID: "user-report-\(report.requireID().uuidString)",
			req: req
		)
		return Response(status: .created)
	}

	func reportFeedback(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(FeedbackRequest.self)
		guard (1 ... 40).contains(body.category.count), (1 ... 10000).contains(body.message.count) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Feedback is empty or too long.", field: "message")
		}
		guard let reporter = try await User.find(payload.sub, on: req.db) else { throw Abort(.unauthorized) }
		try await sendModerationNotification(
			title: "Feedback: \(body.category)",
			body: reporter.displayName,
			collapseID: "feedback-\(UUID().uuidString)",
			req: req
		)
		return Response(status: .created)
	}

	private func sendModerationNotification(
		title: String,
		body: String,
		collapseID: String,
		req: Request
	) async throws {
		do {
			try await NotificationService().sendToAdministrators(
				title: title,
				body: body,
				threadID: "administration-moderation",
				collapseID: collapseID,
				on: req
			)
		} catch {
			req.logger.error("Moderation notification delivery failed: \(error.localizedDescription)")
		}
	}
}
