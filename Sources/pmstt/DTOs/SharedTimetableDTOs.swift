import Foundation
import Vapor

struct SharedTimetablePreview: Content, Equatable {
	let id: UUID
	let title: String
	let authorAccountID: UUID
	let authorDisplayName: String
	let sourceKind: SourceKind
	let revision: Int
	let updatedAt: Date?
	let subjectCount: Int
	let weeklyLessonCount: Int
	let isImportable: Bool
}

enum ReceivedTimetableAvailability: String, Content {
	case available
	case deleted
}

struct AuthoritativeReceivedTimetableDTO: Content {
	let importID: UUID
	let id: UUID
	let title: String?
	let authorAccountID: UUID?
	let authorDisplayName: String?
	let sourceKind: SourceKind?
	let subjects: [TimetableSubjectDTO]
	let revision: Int?
	let updatedAt: Date?
	let importedAt: Date
	let availability: ReceivedTimetableAvailability
}

struct ReceivedTimetableImportRequest: Content {
	let timetableID: UUID

	init(timetableID: UUID) {
		self.timetableID = timetableID
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: AnyCodingKey.self)
		let keys = container.allKeys
		guard keys.count == 1, keys.first?.stringValue == "timetableID" else {
			throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The import body must contain only timetableID."))
		}
		timetableID = try container.decode(UUID.self, forKey: AnyCodingKey(stringValue: "timetableID")!)
	}
}

private struct AnyCodingKey: CodingKey {
	let stringValue: String
	let intValue: Int?
	init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
	init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

struct ReceivedTimetableImportResponse: Content {
	let importID: UUID
	let id: UUID
	let title: String
	let authorAccountID: UUID
	let authorDisplayName: String
	let sourceKind: SourceKind
	let revision: Int
	let updatedAt: Date?
	let importedAt: Date
	let availability: ReceivedTimetableAvailability
}
