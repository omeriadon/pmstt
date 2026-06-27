//
//  startLiveActivity.swift
//  pmstt
//
//  Created by Adon Omeri on 14/5/2026.
//

import Foundation
import AsyncHTTPClient
import NIO

func startLiveActivity(token: String, jwt: String) async throws {
	var request = HTTPClientRequest(
		url: "https://api.push.apple.com/3/device/\(token)"
	)

	request.method = .POST
	request.headers.add(name: "apns-push-type", value: "liveactivity")
	request.headers.add(name: "apns-topic", value: "\(bundleId).push-type.liveactivity")
	request.headers.add(name: "authorization", value: "bearer \(jwt)")

	request.body = .bytes(ByteBuffer(string: """
	{
	  "aps": {
		"event": "start",
		"timestamp": \(Int(Date().timeIntervalSince1970)),
		"content-state": {
		  "remainingSeconds": 3600
		},
		"attributes-type": "TimerAttributes",
		"attributes": {
		  "title": "Exam"
		}
	  }
	}
	"""))

	try await APNSClient().send(request: request)
}
