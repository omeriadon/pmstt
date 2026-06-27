import Vapor

enum ServerErrorCode: String, Codable, Sendable {
	case invalidRequest
	case notFound
	case unauthorized
	case conflict
	case rateLimited
	case internalServerError
}

struct ServerErrorResponse: Content {
	let code: ServerErrorCode
	let message: String
	let field: String?
	let requestID: String
}

struct AppError: AbortError, DebuggableError {
	let status: HTTPResponseStatus
	let code: ServerErrorCode
	let reason: String
	let field: String?

	var identifier: String {
		code.rawValue
	}

	init(
		_ status: HTTPResponseStatus,
		code: ServerErrorCode,
		reason: String,
		field: String? = nil
	) {
		self.status = status
		self.code = code
		self.reason = reason
		self.field = field
	}
}
