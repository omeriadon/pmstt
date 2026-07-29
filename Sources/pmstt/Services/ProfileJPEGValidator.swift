import Crypto
import Foundation
import Vapor

struct ValidatedProfileJPEG {
	let data: Data
	let width: Int
	let height: Int
	let checksum: String
}

enum ProfileJPEGValidator {
	static let maximumBytes = 1_000_000

	static func validateAndSanitize(_ input: Data) throws -> ValidatedProfileJPEG {
		guard input.count <= maximumBytes else {
			throw AppError(.payloadTooLarge, code: .invalidRequest, reason: "Profile photos must be one megabyte or smaller.")
		}
		guard input.starts(with: [0xFF, 0xD8]) else {
			throw AppError(.unsupportedMediaType, code: .invalidRequest, reason: "Only JPEG profile photos are supported.")
		}

		let bytes = [UInt8](input)
		var sanitized = Data([0xFF, 0xD8])
		var index = 2
		var dimensions: (width: Int, height: Int)?

		while index + 3 < bytes.count {
			guard bytes[index] == 0xFF else {
				throw AppError(.badRequest, code: .invalidRequest, reason: "The JPEG profile photo is malformed.")
			}
			let marker = bytes[index + 1]
			if marker == 0xDA {
				sanitized.append(contentsOf: bytes[index...])
				break
			}
			if marker == 0xD9 {
				sanitized.append(contentsOf: [0xFF, 0xD9])
				break
			}
			guard index + 4 <= bytes.count else {
				throw malformedImageError()
			}
			let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
			guard length >= 2, index + 2 + length <= bytes.count else {
				throw malformedImageError()
			}

			if isStartOfFrame(marker), length >= 7 {
				let height = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
				let width = Int(bytes[index + 7]) << 8 | Int(bytes[index + 8])
				dimensions = (width, height)
			}

			if shouldRetain(marker) {
				sanitized.append(contentsOf: bytes[index ..< index + 2 + length])
			}
			index += 2 + length
		}

		guard let dimensions, dimensions.width > 0, dimensions.height > 0 else {
			throw malformedImageError()
		}
		guard dimensions.width == dimensions.height else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Profile photos must be square.")
		}
		guard sanitized.count <= maximumBytes else {
			throw AppError(.payloadTooLarge, code: .invalidRequest, reason: "Profile photos must be one megabyte or smaller.")
		}

		let checksum = SHA256.hash(data: sanitized)
			.map { String(format: "%02x", $0) }
			.joined()
		return ValidatedProfileJPEG(
			data: sanitized,
			width: dimensions.width,
			height: dimensions.height,
			checksum: checksum
		)
	}

	private static func isStartOfFrame(_ marker: UInt8) -> Bool {
		[0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].contains(marker)
	}

	private static func shouldRetain(_ marker: UInt8) -> Bool {
		switch marker {
			case 0xE0 ... 0xEF, 0xFE:
				false
			default:
				true
		}
	}

	private static func malformedImageError() -> AppError {
		AppError(.badRequest, code: .invalidRequest, reason: "The JPEG profile photo is malformed.")
	}
}
