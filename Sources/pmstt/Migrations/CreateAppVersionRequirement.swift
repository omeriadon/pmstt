import Fluent
import FluentSQL

struct CreateAppVersionRequirement: AsyncMigration {
	func prepare(on database: any Database) async throws {
		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw(
				"""
				CREATE TABLE IF NOT EXISTS "app_version_requirements" (
					"id" UUID PRIMARY KEY,
					"app_version" TEXT NOT NULL,
					"app_build" BIGINT NOT NULL,
					"mac_version" TEXT NOT NULL,
					"mac_build" BIGINT NOT NULL
				)
				"""
			).run()
		} else {
			try await database.schema(AppVersionRequirement.schema)
				.id()
				.field("app_version", .string, .required)
				.field("app_build", .int, .required)
				.field("mac_version", .string, .required)
				.field("mac_build", .int, .required)
				.create()
		}

		guard try await AppVersionRequirement.query(on: database).count() == 0 else {
			return
		}

		try await AppVersionRequirement(
			appVersion: "0.0.0",
			appBuild: 0,
			macVersion: "0.0.0",
			macBuild: 0
		).create(on: database)
	}

	func revert(on database: any Database) async throws {
		try await database.schema(AppVersionRequirement.schema).delete()
	}
}
