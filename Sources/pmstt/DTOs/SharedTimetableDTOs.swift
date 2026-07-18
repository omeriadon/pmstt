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

enum TimetableShareAliasAvailabilityReason: String, Content {
	case empty, tooShort, tooLong, invalidCharacter, leadingSeparator, trailingSeparator
	case consecutiveSeparators, reserved, uuidShaped, taken
}

struct TimetableShareAliasResponse: Content {
	let alias: String?
	let timetableID: UUID?
	let url: String?
}

struct TimetableShareAliasAvailabilityResponse: Content {
	let normalizedAlias: String
	let isValid: Bool
	let isAvailable: Bool
	let isOwnedByCurrentUser: Bool
	let reason: TimetableShareAliasAvailabilityReason?
}

struct TimetableShareAliasUpdateRequest: Content {
	let alias: String
	init(alias: String) {
		self.alias = alias
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: AnyCodingKey.self)
		guard container.allKeys.count == 1, container.allKeys.first?.stringValue == "alias" else {
			throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The alias body must contain only alias."))
		}
		alias = try container.decode(String.self, forKey: AnyCodingKey(stringValue: "alias")!)
	}
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
	let timetableID: UUID?
	let timetableLocator: String?

	var locator: String {
		if let timetableLocator {
			return timetableLocator
		}
		return timetableID?.uuidString ?? ""
	}

	init(timetableID: UUID) {
		self.timetableID = timetableID
		timetableLocator = nil
	}

	init(timetableLocator: String) {
		timetableID = nil
		self.timetableLocator = timetableLocator
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: AnyCodingKey.self)
		let keys = container.allKeys
		guard keys.count == 1 else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The import body must contain exactly one locator.")) }
		if keys.first?.stringValue == "timetableID" {
			timetableID = try container.decode(UUID.self, forKey: AnyCodingKey(stringValue: "timetableID")!)
			timetableLocator = nil
		} else if keys.first?.stringValue == "timetableLocator" {
			timetableID = nil
			timetableLocator = try container.decode(String.self, forKey: AnyCodingKey(stringValue: "timetableLocator")!)
		} else {
			throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The import body must contain exactly one locator."))
		}
	}
}

private struct AnyCodingKey: CodingKey {
	let stringValue: String
	let intValue: Int?
	init?(stringValue: String) {
		self.stringValue = stringValue; intValue = nil
	}

	init?(intValue: Int) {
		stringValue = String(intValue); self.intValue = intValue
	}
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
