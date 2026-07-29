import Vapor

enum ServerErrorCode: String, Codable {
	case accountNotFound
	case invalidRequest
	case invalidCredentials
	case notFound
	case unauthorized
	case emailAlreadyExists
	case verificationCodeInvalid
	case verificationCodeExpired
	case verificationCodeUsed
	case sessionExpired
	case timetableConflict
	case invalidTimetable
	case conflict
	case aliasTaken
	case rateLimited
	case developmentAccessRestricted
	case profileStorageCapacityReached
	case profileStorageWriteBudgetReached
	case profileStorageOperationBudgetReached
	case internalServerError
}

struct ServerErrorResponse: Content {
	let code: ServerErrorCode
	let message: String
	let field: String?
	let headers: HTTPHeaders
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
		field: String? = nil,
		headers: HTTPHeaders = [:]
	) {
		self.status = status
		self.code = code
		self.reason = reason
		self.field = field
		self.headers = headers
	}
}
