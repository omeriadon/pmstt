import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import JWT
import Vapor

public func configure(_ app: Application) async throws {
	app.middleware.use(RequestIDMiddleware())
	app.middleware.use(StructuredErrorMiddleware(environment: app.environment))

	// Configure JWT keys for access tokens
	let jwtSecret = Environment.get("JWT_SECRET") ?? "pmstt-development-secret-key-that-is-at-least-32-bytes"
	await app.jwt.keys.add(hmac: HMACKey(from: jwtSecret), digestAlgorithm: .sha256)
	app.jwt.apple.applicationIdentifier = Environment.get("TIMETABLE_APPLE_APPLICATION_IDENTIFIER") ?? "com.omeriadon.Timetable"

	if app.environment == .testing {
		app.databases.use(.sqlite(.memory), as: .sqlite)
		app.logger.info("Configured in-memory SQLite database for tests")
	} else {
		let databasePort = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432
		let databaseHostname = Environment.get("DATABASE_HOSTNAME") ?? "127.0.0.1"
		let databaseName = Environment.get("DATABASE_NAME") ?? "pmstt"
		let databaseUsername = Environment.get("DATABASE_USERNAME") ?? "pmstt"

		let serverPort = Environment.get("PORT").flatMap(Int.init) ?? 8081
		let serverHostname = Environment.get("HOSTNAME") ?? "127.0.0.1"

		app.http.server.configuration.hostname = serverHostname
		app.http.server.configuration.port = serverPort

		app.databases.use(
			.postgres(
				configuration: SQLPostgresConfiguration(
					hostname: databaseHostname,
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
	app.migrations.add(CreatePassRecord())
	app.migrations.add(CreatePassRegistration())
	app.migrations.add(CreateReceivedPassMirror())
	app.migrations.add(CreateReceivedNameOverride())
	app.migrations.add(CreateUserDevice())

	try routes(app)
	app.logger.info("pmstt configuration complete")
}
