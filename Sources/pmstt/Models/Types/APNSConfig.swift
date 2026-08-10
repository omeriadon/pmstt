//
//  APNSConfig.swift
//  pmstt
//
//  Created by Adon Omeri on 14/5/2026.
//

import Foundation
import Vapor

struct APNSConfig {
	let teamId: String
	let keyId: String
	let bundleId: String
	let privateKeyPath: String

	static func load(isDebug: Bool) throws -> Self {
		guard let teamID = Environment.get("APNS_TEAM_ID") else {
			throw AppError(.serviceUnavailable, code: .internalServerError, reason: "APNs is not configured.")
		}

		let keyID = isDebug
			? Environment.get("APNS_DEBUG_KEY_ID")
			: Environment.get("APNS_PRODUCTION_KEY_ID")
		let privateKeyPath = isDebug
			? Environment.get("APNS_DEBUG_PRIVATE_KEY_PATH")
			: Environment.get("APNS_PRODUCTION_PRIVATE_KEY_PATH")

		guard let keyID = keyID ?? Environment.get("APNS_KEY_ID"),
		      let privateKeyPath = privateKeyPath ?? Environment.get("APNS_PRIVATE_KEY_PATH")
		else {
			throw AppError(.serviceUnavailable, code: .internalServerError, reason: "APNs is not configured.")
		}

		return Self(
			teamId: teamID,
			keyId: keyID,
			bundleId: Environment.get("APNS_BUNDLE_ID") ?? "com.omeriadon.Timetable",
			privateKeyPath: privateKeyPath
		)
	}
}
