import Vapor

struct StructuredErrorMiddleware: AsyncMiddleware {
	let environment: Environment

	func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
		do {
			return try await next.respond(to: request)
		} catch {
			let appError = error as? AppError
			let abortError = error as? any AbortError
			let status = appError?.status ?? abortError?.status ?? .internalServerError
			let code = appError?.code ?? defaultCode(for: status)
			let message = appError?.reason
				?? abortError?.reason
				?? (environment == .production ? "An unexpected error occurred." : String(describing: error))

			request.logger.report(error: error)

			if request.headers.first(name: .accept)?.contains("text/html") == true {
				let response = Response(status: status)
				response.headers.contentType = .html
				response.body = .init(string: """
				<!doctype html>
				<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Timetable link unavailable</title></head><body><main><h1>Timetable link unavailable</h1><p>\(htmlEscaped(message))</p></main></body></html>
				""")
				response.headers.replaceOrAdd(name: RequestIDMiddleware.headerName, value: request.requestID)
				return response
			}

			let payload = ServerErrorResponse(
				code: code,
				message: message,
				field: appError?.field,
				requestID: request.requestID
			)
			let response = Response(status: status)
			response.headers.contentType = .json
			response.body = try .init(data: JSONEncoder().encode(payload))
			response.headers.replaceOrAdd(name: RequestIDMiddleware.headerName, value: request.requestID)
			return response
		}
	}

	private func htmlEscaped(_ value: String) -> String {
		value
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "'", with: "&#39;")
	}

	private func defaultCode(for status: HTTPResponseStatus) -> ServerErrorCode {
		switch status {
			case .unauthorized, .forbidden:
				.unauthorized
			case .notFound:
				.notFound
			case .conflict:
				.conflict
			case .tooManyRequests:
				.rateLimited
			case _ where status.code >= 500:
				.internalServerError
			default:
				.invalidRequest
		}
	}
}
