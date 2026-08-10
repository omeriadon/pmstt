import Fluent
import Vapor

struct AppVersionController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		routes.get("v1", "app-version", use: requirement)
	}

	private func requirement(req: Request) async throws -> AppVersionCheckResponse {
		guard let installedVersion = req.query[String.self, at: "version"],
		      let installedBuild = req.query[Int.self, at: "build"],
		      let platform = req.query[String.self, at: "platform"]
		else {
			throw Abort(.badRequest)
		}

		let requirements = try await AppVersionRequirementService.current(on: req.db)
		let requiredVersion = platform == ClientPlatform.macOS.rawValue
			? requirements.macVersion
			: requirements.appVersion
		let requiredBuild = platform == ClientPlatform.macOS.rawValue
			? requirements.macBuild
			: requirements.appBuild

		return AppVersionCheckResponse(
			requiresUpdate: Self.isOlder(
				version: installedVersion,
				build: installedBuild,
				thanVersion: requiredVersion,
				build: requiredBuild
			),
			requiredVersion: requiredVersion,
			requiredBuild: requiredBuild
		)
	}

	private static func isOlder(
		version installedVersion: String,
		build installedBuild: Int,
		thanVersion requiredVersion: String,
		build requiredBuild: Int
	) -> Bool {
		let installedComponents = installedVersion.split(separator: ".").map { Int($0) ?? 0 }
		let requiredComponents = requiredVersion.split(separator: ".").map { Int($0) ?? 0 }
		for index in 0 ..< max(installedComponents.count, requiredComponents.count) {
			let installed = installedComponents.indices.contains(index) ? installedComponents[index] : 0
			let required = requiredComponents.indices.contains(index) ? requiredComponents[index] : 0
			if installed != required {
				return installed < required
			}
		}
		return installedBuild < requiredBuild
	}
}

enum AppVersionRequirementService {
	static func current(on database: any Database) async throws -> AppVersionRequirement {
		if let requirement = try await AppVersionRequirement.query(on: database).first() {
			return requirement
		}
		let requirement = AppVersionRequirement()
		try await requirement.create(on: database)
		return requirement
	}
}

struct AppVersionRequirementResponse: Content {
	let appVersion: String
	let appBuild: Int
	let macVersion: String
	let macBuild: Int

	init(_ requirement: AppVersionRequirement) {
		appVersion = requirement.appVersion
		appBuild = requirement.appBuild
		macVersion = requirement.macVersion
		macBuild = requirement.macBuild
	}
}

struct AppVersionRequirementUpdateRequest: Content {
	let appVersion: String
	let appBuild: Int
	let macVersion: String
	let macBuild: Int
}

private struct AppVersionCheckResponse: Content {
	let requiresUpdate: Bool
	let requiredVersion: String
	let requiredBuild: Int
}
