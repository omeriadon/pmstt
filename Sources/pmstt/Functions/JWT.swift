//
//  JWT.swift
//  pmstt
//
//  Created by Adon Omeri on 14/5/2026.
//

import Foundation
import JWT

struct APNSPayload: JWTPayload {
	let iss: IssuerClaim
	let iat: IssuedAtClaim

	func verify(using _: some JWTAlgorithm) async throws {}
}

func makeJWT(config: APNSConfig) async throws -> String {
	let pem = try String(contentsOfFile: config.privateKeyPath, encoding: .utf8)

	let key = try ES256PrivateKey(pem: pem)

	let keys = JWTKeyCollection()

	let kid = JWKIdentifier(string: config.keyId)

	await keys.add(
		ecdsa: key,
		kid: kid
	)

	let payload = APNSPayload(
		iss: .init(value: config.teamId),
		iat: .init(value: Date())
	)

	return try await keys.sign(
		payload,
		kid: kid
	)
}
