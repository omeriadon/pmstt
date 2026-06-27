//
//  File.swift
//  pmstt
//
//  Created by Adon Omeri on 14/5/2026.
//

import Foundation

func getPushStartTokens() -> [String] {
	let url = URL(fileURLWithPath: "/var/lib/pmstt/tokens.json")

	do {
		let data = try Data(contentsOf: url)
		return try JSONDecoder().decode([String].self, from: data)
	} catch {
		return []
	}
}

func savePushStartToken(_ token: String) {
	let url = URL(fileURLWithPath: "/var/lib/pmstt/tokens.json")

	do {
		let data = try JSONEncoder().encode(token)
		try data.write(to: url, options: [.atomic])
	} catch {
		print("Failed to save token:", error)
	}
}
