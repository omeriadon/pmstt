import Fluent
import FluentSQLiteDriver
import Foundation
@testable import pmstt
import Testing
import Vapor

@Suite("Live Activity delivery idempotency")
struct LiveActivityIdempotencyTests {
	@Test("A transition can be claimed only once per activity")
	func uniqueTransitionClaim() async throws {
		let app = try await Application.make(.testing)
		app.databases.use(.sqlite(.memory), as: .sqlite)
		try await app.db.schema(SchoolDayLiveActivity.schema)
			.id()
			.field("user_device_id", .uuid, .required)
			.field("activity_key", .string, .required)
			.field("school_date", .string, .required)
			.field("update_token", .string)
			.field("current_transition", .string, .required)
			.field("status", .string, .required)
			.field("last_apns_timestamp", .datetime)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.create()
		try await app.db.schema(SchoolDayLiveActivityTransition.schema)
			.id()
			.field("live_activity_id", .uuid, .required)
			.field("transition", .string, .required)
			.field("created_at", .datetime)
			.unique(on: "live_activity_id", "transition")
			.create()

		let activity = SchoolDayLiveActivity(
			userDeviceID: UUID(),
			activityKey: UUID().uuidString,
			schoolDate: "2026-07-03",
			currentTransition: "pending"
		)
		try await activity.create(on: app.db)

		try await SchoolDayLiveActivityTransition(liveActivityID: try activity.requireID(), transition: "period1").create(on: app.db)
		var duplicateWasRejected = false
		do {
			try await SchoolDayLiveActivityTransition(liveActivityID: try activity.requireID(), transition: "period1").create(on: app.db)
		} catch {
			duplicateWasRejected = true
		}
		#expect(duplicateWasRejected)
		try await app.asyncShutdown()
	}
}
