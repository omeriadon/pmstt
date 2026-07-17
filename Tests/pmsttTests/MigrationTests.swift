import Fluent
import FluentSQLiteDriver
import Vapor
import XCTest
@testable import pmstt

final class MigrationTests: XCTestCase {
	func testFreshDatabaseMigratesAndRollsBack() async throws {
		let migrations = receivedPassMirrorMigrationList()
		let app = try await makeTestingApplication(with: migrations)
		addTeardownBlock { try await app.asyncShutdown() }

		try await app.migrator.setupIfNeeded().flatMap { app.migrator.prepareBatch() }.get()
		try await assertMigrationCount(migrations.count, on: app)

		try await app.migrator.setupIfNeeded().flatMap { app.migrator.revertAllBatches() }.get()
		try await assertMigrationCount(0, on: app)

		try await app.migrator.setupIfNeeded().flatMap { app.migrator.prepareBatch() }.get()
		try await assertMigrationCount(migrations.count, on: app)
	}

	func testExistingDatabaseUpgradesSequentially() async throws {
		let migrations = receivedPassMirrorMigrationList()
		let app = try await makeTestingApplication(with: Array(migrations.prefix(2)))
		addTeardownBlock { try await app.asyncShutdown() }

		try await app.migrator.setupIfNeeded().flatMap { app.migrator.prepareBatch() }.get()
		try await assertMigrationCount(2, on: app)

		app.migrations.add(Array(migrations.dropFirst(2)))
		try await app.migrator.setupIfNeeded().flatMap { app.migrator.prepareBatch() }.get()
		try await assertMigrationCount(migrations.count, on: app)
	}

	private func receivedPassMirrorMigrationList() -> [any Migration] {
		[CreateUser(), CreateReceivedPassMirror(), AddContentRevisionToReceivedPassMirror()]
	}

	private func makeTestingApplication(with migrations: [any Migration]) async throws -> Application {
		let app = try await Application.make(.testing)
		app.databases.use(.sqlite(.memory), as: .sqlite)
		app.migrations.add(migrations)
		try await app.migrator.setupIfNeeded().get()
		return app
	}

	private func assertMigrationCount(_ expected: Int, on app: Application) async throws {
		let count = try await MigrationLog.query(on: app.db(.sqlite)).count()
		XCTAssertEqual(count, expected)
	}
}
