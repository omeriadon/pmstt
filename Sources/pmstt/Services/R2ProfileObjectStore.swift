import Crypto
import Foundation
import NIOCore
import Vapor

struct R2StoredObject {
	let etag: String
}

struct R2ProfileObjectStore {
	private let configuration: ProfileStorageConfiguration

	init(configuration: ProfileStorageConfiguration) {
		self.configuration = configuration
	}

	func put(
		key: String,
		data: Data,
		contentType: String,
		client: any Client
	) async throws -> R2StoredObject {
		let response = try await send(
			method: .PUT,
			key: key,
			body: data,
			contentType: contentType,
			client: client
		)
		guard response.status == .ok || response.status == .created else {
			throw Abort(.badGateway, reason: "Profile photo storage rejected the upload.")
		}
		return R2StoredObject(etag: response.headers.first(name: .eTag)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? sha256Hex(data))
	}

	func get(key: String, client: any Client) async throws -> ClientResponse {
		let response = try await send(method: .GET, key: key, body: Data(), contentType: nil, client: client)
		guard response.status == .ok else {
			throw Abort(.badGateway, reason: "Profile photo storage could not read the object.")
		}
		return response
	}

	func delete(key: String, client: any Client) async throws {
		let response = try await send(method: .DELETE, key: key, body: Data(), contentType: nil, client: client)
		guard response.status == .noContent || response.status == .ok else {
			throw Abort(.badGateway, reason: "Profile photo storage could not delete the object.")
		}
	}

	private func send(
		method: HTTPMethod,
		key: String,
		body: Data,
		contentType: String?,
		client: any Client
	) async throws -> ClientResponse {
		let timestamp = Date.now
		let amzDate = Self.amzDate(timestamp)
		let dateStamp = Self.dateStamp(timestamp)
		let payloadHash = sha256Hex(body)
		let canonicalURI = "/\(configuration.bucketName)/\(key)"
		let host = "\(configuration.accountID).r2.cloudflarestorage.com"
		var signedHeaderNames = "host;x-amz-content-sha256;x-amz-date"
		var canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"

		if let contentType {
			signedHeaderNames = "content-type;\(signedHeaderNames)"
			canonicalHeaders = "content-type:\(contentType)\n\(canonicalHeaders)"
		}

		let canonicalRequest = [
			method.rawValue,
			canonicalURI,
			"",
			canonicalHeaders,
			signedHeaderNames,
			payloadHash,
		].joined(separator: "\n")
		let scope = "\(dateStamp)/auto/s3/aws4_request"
		let stringToSign = [
			"AWS4-HMAC-SHA256",
			amzDate,
			scope,
			sha256Hex(Data(canonicalRequest.utf8)),
		].joined(separator: "\n")
		let signingKey = signatureKey(dateStamp: dateStamp)
		let signature = hmacHex(key: signingKey, data: Data(stringToSign.utf8))

		var headers = HTTPHeaders()
		headers.replaceOrAdd(name: .host, value: host)
		headers.replaceOrAdd(name: "x-amz-content-sha256", value: payloadHash)
		headers.replaceOrAdd(name: "x-amz-date", value: amzDate)
		headers.replaceOrAdd(
			name: .authorization,
			value: "AWS4-HMAC-SHA256 Credential=\(configuration.accessKeyID)/\(scope), SignedHeaders=\(signedHeaderNames), Signature=\(signature)"
		)
		if let contentType {
			headers.contentType = HTTPMediaType.parse(contentType)
		}

		let uri = URI(string: "\(configuration.endpoint)\(canonicalURI)")
		switch method {
			case .PUT:
				return try await client.put(uri, headers: headers) { clientRequest in
					clientRequest.body = ByteBuffer(data: body)
				}
			case .GET:
				return try await client.get(uri, headers: headers)
			case .DELETE:
				return try await client.delete(uri, headers: headers)
			default:
				throw Abort(.internalServerError, reason: "Unsupported profile object operation.")
		}
	}

	private func signatureKey(dateStamp: String) -> Data {
		let dateKey = hmac(key: Data("AWS4\(configuration.secretAccessKey)".utf8), data: Data(dateStamp.utf8))
		let regionKey = hmac(key: dateKey, data: Data("auto".utf8))
		let serviceKey = hmac(key: regionKey, data: Data("s3".utf8))
		return hmac(key: serviceKey, data: Data("aws4_request".utf8))
	}

	private func hmac(key: Data, data: Data) -> Data {
		Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
	}

	private func hmacHex(key: Data, data: Data) -> String {
		hmac(key: key, data: data).map { String(format: "%02x", $0) }.joined()
	}

	private func sha256Hex(_ data: Data) -> String {
		SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}

	private static func amzDate(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
		return formatter.string(from: date)
	}

	private static func dateStamp(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyyMMdd"
		return formatter.string(from: date)
	}
}
