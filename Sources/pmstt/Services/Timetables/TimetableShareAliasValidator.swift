import Foundation

enum TimetableShareAliasValidationReason: String, Codable, Sendable {
	case empty
	case tooShort
	case tooLong
	case invalidCharacter
	case leadingSeparator
	case trailingSeparator
	case consecutiveSeparators
	case reserved
	case uuidShaped
}

struct TimetableShareAliasValidationError: Error, Equatable, Sendable {
	let reason: TimetableShareAliasValidationReason
	let character: Character?
	let scalarIndex: Int?
}

enum TimetableShareAliasValidator {
	static let minimumLength = 3
	static let maximumLength = 30
	static let reservedAliases: Set<String> = [
		"api", "v1", "health", "admin", "account", "auth", "login", "logout", "settings",
		"search", "share", "shared", "sharedtimetable", "timetable", "timetables", "messages",
		"support", "privacy", "terms", "null", "undefined", "me", "owner",
	]

	static func canonicalize(_ raw: String) -> String {
		raw.lowercased()
	}

	static func isReserved(_ alias: String) -> Bool {
		reservedAliases.contains(canonicalize(alias))
	}

	static func validate(_ raw: String) -> TimetableShareAliasValidationError? {
		let alias = canonicalize(raw)
		guard !alias.isEmpty else { return .init(reason: .empty, character: nil, scalarIndex: nil) }
		guard UUID(uuidString: alias) == nil else { return .init(reason: .uuidShaped, character: nil, scalarIndex: nil) }
		guard alias.count >= minimumLength else { return .init(reason: .tooShort, character: nil, scalarIndex: nil) }
		guard alias.count <= maximumLength else { return .init(reason: .tooLong, character: nil, scalarIndex: nil) }

		let characters = Array(alias)
		for (index, character) in characters.enumerated() {
			let valid = character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
			guard valid else { return .init(reason: .invalidCharacter, character: character, scalarIndex: index) }
		}
		if characters.first == "-" || characters.first == "_" {
			return .init(reason: .leadingSeparator, character: characters[0], scalarIndex: 0)
		}
		if characters.last == "-" || characters.last == "_" {
			return .init(reason: .trailingSeparator, character: characters[characters.count - 1], scalarIndex: characters.count - 1)
		}
		for index in 1 ..< characters.count where isSeparator(characters[index - 1]) && isSeparator(characters[index]) {
			return .init(reason: .consecutiveSeparators, character: characters[index], scalarIndex: index)
		}
		if isReserved(alias) {
			return .init(reason: .reserved, character: nil, scalarIndex: nil)
		}
		return nil
	}

	static func validateAndCanonicalize(_ raw: String) throws -> String {
		let alias = canonicalize(raw)
		if let error = validate(alias) {
			throw error
		}
		return alias
	}

	private static func isSeparator(_ character: Character) -> Bool {
		character == "-" || character == "_"
	}
}
