import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Vapor
import JWT

public func configure(_ app: Application) async throws {
	app.middleware.use(RequestIDMiddleware())
	app.middleware.use(StructuredErrorMiddleware(environment: app.environment))

	// Configure JWT keys for access tokens
	let jwtSecret = Environment.get("JWT_SECRET") ?? "pmstt-development-secret-key-that-is-at-least-32-bytes"
	await app.jwt.keys.add(hmac: HMACKey(from: jwtSecret), digestAlgorithm: .sha256)


	if app.environment == .testing {
		app.databases.use(.sqlite(.memory), as: .sqlite)
		app.logger.info("Configured in-memory SQLite database for tests")
	} else {
		let databasePort = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432
		let databaseName = Environment.get("DATABASE_NAME") ?? "pmstt"
		let databaseUsername = Environment.get("DATABASE_USERNAME") ?? "pmstt"

		app.databases.use(
			.postgres(
				configuration: SQLPostgresConfiguration(
					hostname: Environment.get("DATABASE_HOST") ?? "localhost",
					port: databasePort,
					username: databaseUsername,
					password: Environment.get("DATABASE_PASSWORD"),
					database: databaseName,
					tls: .disable
				),
				sqlLogLevel: .info
			),
			as: .psql
		)
		app.logger.info("Configured PostgreSQL database", metadata: ["database": .string(databaseName)])
	}

	app.migrations.add(CreateUser())
	app.migrations.add(CreateUserToken())
	app.migrations.add(CreateOwnerTimetable())
	app.migrations.add(CreateAuthoredTimetable())

	try routes(app)
	app.logger.info("pmstt configuration complete")
}
