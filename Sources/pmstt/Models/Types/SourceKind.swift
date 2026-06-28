import Foundation

enum SourceKind: String, Codable {
	case accountOwner
	case authoredForThirdParty

	static let `default`: Self = .accountOwner

	init(rawValueOrDefault rawValue: String, default defaultValue: Self = .default) {
		self = Self(rawValue: rawValue) ?? defaultValue
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		try self.init(rawValueOrDefault: container.decode(String.self))
	}
}
