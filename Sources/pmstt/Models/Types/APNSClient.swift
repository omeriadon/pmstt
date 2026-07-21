//
//  APNSClient.swift
//  pmstt
//
//  Created by Adon Omeri on 14/5/2026.
//

import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1

final class APNSClient {
	let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

	struct Response: Sendable {
		let status: HTTPResponseStatus
		let reason: String?
	}

	func send(request: HTTPClientRequest) async throws -> Response {
		let client = HTTPClient(eventLoopGroupProvider: .shared(group))
		let response = try await client.execute(request, timeout: .seconds(10))
		let body = try await response.body.collect(upTo: 64 * 1024)
		try await client.shutdown()

		struct ErrorResponse: Decodable {
			let reason: String?
		}

		let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) ?? Data()
		let reason = (try? JSONDecoder().decode(ErrorResponse.self, from: bodyData))?.reason
		let fallback = bodyData.isEmpty ? nil : String(data: bodyData, encoding: .utf8)
		return Response(status: response.status, reason: reason ?? fallback)
	}
}
