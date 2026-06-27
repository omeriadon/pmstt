//
//  File.swift
//  pmstt
//
//  Created by Adon Omeri on 14/5/2026.
//

import Foundation
import NIO
import NIOHTTP1
import AsyncHTTPClient

final class APNSClient {
	let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

	func send(request: HTTPClientRequest) async throws {
		let client = HTTPClient(eventLoopGroupProvider: .shared(group))
		_ = try await client.execute(request, timeout: .seconds(10))
		try await client.shutdown()
	}
}
