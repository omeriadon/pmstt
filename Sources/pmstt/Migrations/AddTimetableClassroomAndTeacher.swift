import Fluent
import Foundation

struct AddTimetableClassroomAndTeacher: AsyncMigration {
	func prepare(on database: any Database) async throws {
		for timetable in try await OwnerTimetable.query(on: database).all() {
			timetable.subjectsData = try migratedSubjectsData(timetable.subjectsData)
			try await timetable.save(on: database)
		}

		for timetable in try await AuthoredTimetable.query(on: database).all() {
			timetable.subjectsData = try migratedSubjectsData(timetable.subjectsData)
			try await timetable.save(on: database)
		}

		for timetable in try await ReceivedPassMirror.query(on: database).all() {
			timetable.subjectsData = try migratedSubjectsData(timetable.subjectsData)
			try await timetable.save(on: database)
		}
	}

	func revert(on _: any Database) async throws {}

	private func migratedSubjectsData(_ data: Data) throws -> Data {
		let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: data)
		return try JSONEncoder().encode(subjects)
	}
}
