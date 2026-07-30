import Fluent
import Foundation
import Vapor

enum ProfileContentKind: String, Content {
	case photo
	case monogram
	case emoji
}

enum ProfileFontDesign: String, Content {
	case `default`
	case serif
	case monospaced
	case rounded
}

enum ProfileFontWeight: String, Content {
	case regular
	case medium
	case semibold
	case bold
	case heavy
}

struct ProfileColorDTO: Content {
	let red: Double
	let green: Double
	let blue: Double
	let alpha: Double

	private enum CodingKeys: String, CodingKey {
		case red = "r"
		case green = "g"
		case blue = "b"
		case alpha = "a"
	}
}

struct ProfileAppearanceDTO: Content {
	let version: Int
	let contentKind: ProfileContentKind
	let monogram: String
	let emoji: String
	let fontDesign: ProfileFontDesign
	let fontWeight: ProfileFontWeight
	let colours: [ProfileColorDTO]
	let speed: Double
	let noise: Double

	private enum CodingKeys: String, CodingKey {
		case version
		case contentKind
		case monogram
		case emoji
		case fontDesign
		case fontWeight
		case colours
		case speed
		case noise
		case usesMonogram
		case symbol
		case font
	}

	static let `default` = ProfileAppearanceDTO(
		version: 2,
		contentKind: .emoji,
		monogram: "",
		emoji: "👤",
		fontDesign: .rounded,
		fontWeight: .semibold,
		colours: [
			ProfileColorDTO(red: 0.416, green: 0.655, blue: 1, alpha: 1),
			ProfileColorDTO(red: 0.690, green: 0.424, blue: 1, alpha: 1),
			ProfileColorDTO(red: 0.980, green: 0.616, blue: 0.702, alpha: 1),
		],
		speed: 0.2,
		noise: 64
	)

	init(
		version: Int,
		contentKind: ProfileContentKind,
		monogram: String,
		emoji: String,
		fontDesign: ProfileFontDesign,
		fontWeight: ProfileFontWeight,
		colours: [ProfileColorDTO],
		speed: Double,
		noise: Double
	) {
		self.version = version
		self.contentKind = contentKind
		self.monogram = monogram
		self.emoji = emoji
		self.fontDesign = fontDesign
		self.fontWeight = fontWeight
		self.colours = colours
		self.speed = speed
		self.noise = noise
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
		monogram = try container.decodeIfPresent(String.self, forKey: .monogram) ?? ""
		colours = try container.decodeIfPresent([ProfileColorDTO].self, forKey: .colours) ?? Self.default.colours
		speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 0.2
		noise = try container.decodeIfPresent(Double.self, forKey: .noise) ?? 64

		if let contentKind = try container.decodeIfPresent(ProfileContentKind.self, forKey: .contentKind) {
			self.contentKind = contentKind
			emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "👤"
			fontDesign = try container.decodeIfPresent(ProfileFontDesign.self, forKey: .fontDesign) ?? .rounded
			fontWeight = try container.decodeIfPresent(ProfileFontWeight.self, forKey: .fontWeight) ?? .semibold
		} else {
			let usesMonogram = try container.decodeIfPresent(Bool.self, forKey: .usesMonogram) ?? false
			let symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "person.fill"
			let font = try container.decodeIfPresent(String.self, forKey: .font) ?? "rounded"
			contentKind = usesMonogram ? .monogram : .emoji
			emoji = Self.legacyEmoji(for: symbol)
			fontDesign = ProfileFontDesign(rawValue: font) ?? .rounded
			fontWeight = .semibold
		}
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(version, forKey: .version)
		try container.encode(contentKind, forKey: .contentKind)
		try container.encode(monogram, forKey: .monogram)
		try container.encode(emoji, forKey: .emoji)
		try container.encode(fontDesign, forKey: .fontDesign)
		try container.encode(fontWeight, forKey: .fontWeight)
		try container.encode(colours, forKey: .colours)
		try container.encode(speed, forKey: .speed)
		try container.encode(noise, forKey: .noise)
	}

	func validated() throws -> ProfileAppearanceDTO {
		guard version == 2 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Unsupported profile appearance version.", field: "version")
		}
		guard (1 ... 3).contains(colours.count) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Choose between one and three profile colours.", field: "colours")
		}
		guard colours.allSatisfy(\.isValid) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Profile colours must use values between zero and one.", field: "colours")
		}
		guard monogram.count <= 3 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "A monogram can contain at most three characters.", field: "monogram")
		}
		guard emoji.count <= 8 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Choose one emoji.", field: "emoji")
		}
		return self
	}

	private static func legacyEmoji(for symbol: String) -> String {
		switch symbol {
			case "star.fill":
				"⭐️"
			case "bolt.fill":
				"⚡️"
			case "book.fill":
				"📚"
			case "figure.run":
				"🏃"
			case "music.note":
				"🎵"
			case "gamecontroller.fill":
				"🎮"
			case "paintpalette.fill":
				"🎨"
			case "paperplane.fill":
				"✈️"
			default:
				"👤"
		}
	}
}

struct ProfilePhotoMetadataDTO: Content {
	let revision: Int
	let url: URL
	let contentType: String
	let byteSize: Int
	let width: Int
	let height: Int
	let checksum: String
	let updatedAt: Date
}

struct ProfileBadgeDTO: Content {
	let id: UUID
	let symbol: String
	let backgroundColor: ProfileColorDTO?
	let symbolColor: ProfileColorDTO?
	let priority: Int
	let accessibilityLabel: String
}

extension User {
	var decodedProfileAppearance: ProfileAppearanceDTO {
		guard let profileAppearanceData,
			  let appearance = try? JSONDecoder().decode(ProfileAppearanceDTO.self, from: profileAppearanceData)
		else {
			return .default
		}
		return appearance
	}

	func profilePhotoMetadata(on database: any Database) async throws -> ProfilePhotoMetadataDTO? {
		guard let userID = id,
			  let media = try await ProfileMedia.query(on: database)
				.filter(\.$user.$id == userID)
				.first()
		else {
			return nil
		}
		let publicBaseURL = Environment.get("PUBLIC_BASE_URL") ?? "https://timetable.adonis.pt"
		guard let url = URL(
			string: "\(publicBaseURL)/api/v1/friends/profile/photo/\(userID.uuidString)?revision=\(media.revision)"
		) else {
			throw Abort(.internalServerError, reason: "The public profile photo URL is invalid.")
		}
		return ProfilePhotoMetadataDTO(
			revision: media.revision,
			url: url,
			contentType: media.contentType,
			byteSize: media.byteSize,
			width: media.width,
			height: media.height,
			checksum: media.checksum,
			updatedAt: media.updatedAt ?? .now
		)
	}

	var profileBadges: [ProfileBadgeDTO] {
		switch resolvedAccountAuthority {
			case .systemOwner:
				[
					ProfileBadgeDTO(
						id: UUID(uuid: (0xE9, 0x3D, 0xD9, 0xC4, 0xA5, 0xB1, 0x46, 0x94, 0x97, 0x95, 0xFD, 0x0D, 0x89, 0xC0, 0x5F, 0xB3)),
						symbol: "crown.fill",
						backgroundColor: ProfileColorDTO(red: 0.95, green: 0.65, blue: 0.05, alpha: 1),
						symbolColor: ProfileColorDTO(red: 1, green: 1, blue: 1, alpha: 1),
						priority: 100,
						accessibilityLabel: "Permanent owner"
					),
				]
			case .administrator:
				[
					ProfileBadgeDTO(
						id: UUID(uuid: (0x0F, 0x6C, 0xD4, 0x52, 0x84, 0xAC, 0x44, 0x82, 0x8C, 0x23, 0xA4, 0x8F, 0x5D, 0x56, 0x14, 0x8A)),
						symbol: "checkmark.shield.fill",
						backgroundColor: ProfileColorDTO(red: 0.16, green: 0.45, blue: 0.95, alpha: 1),
						symbolColor: ProfileColorDTO(red: 1, green: 1, blue: 1, alpha: 1),
						priority: 90,
						accessibilityLabel: "Administrator"
					),
				]
			case .user:
				[]
		}
	}
}

extension UserAccountResponse {
	init(user: User, on database: any Database) async throws {
		self.init(
			id: try user.requireID(),
			email: user.email,
			displayName: user.displayName,
			createdAt: user.createdAt,
			authority: user.resolvedAccountAuthority,
			appearance: user.decodedProfileAppearance,
			photo: try await user.profilePhotoMetadata(on: database),
			badges: user.profileBadges,
			revision: user.profileRevision
		)
	}
}

private extension ProfileColorDTO {
	var isValid: Bool {
		[red, green, blue, alpha].allSatisfy { (0 ... 1).contains($0) }
	}
}
