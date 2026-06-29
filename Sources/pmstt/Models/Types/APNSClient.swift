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

	func send(request: HTTPClientRequest) async throws -> HTTPResponseStatus {
		let client = HTTPClient(eventLoopGroupProvider: .shared(group))
		let response = try await client.execute(request, timeout: .seconds(10))
		try await client.shutdown()
		return response.status
	}
}
