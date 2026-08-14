import Vapor

enum AppBackground: String, Content, CaseIterable, Hashable {
	case solid
	case paper

	init(from decoder: any Decoder) throws {
		let value = try decoder.singleValueContainer().decode(String.self)
		self = value == Self.solid.rawValue ? .solid : .paper
	}
}
