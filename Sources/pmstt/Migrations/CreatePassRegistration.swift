import Fluent

struct CreatePassRegistration: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("pass_registrations")
			.id()
			.field("device_library_identifier", .string, .required)
			.field("pass_type_identifier", .string, .required)
			.field("serial_number", .string, .required)
			.field("push_token", .string, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "device_library_identifier", "serial_number")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("pass_registrations").delete()
	}
}
