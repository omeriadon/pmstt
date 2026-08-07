import Foundation
import Vapor

enum GradeAssessmentLocation: String, Codable, Sendable {
	case exam
	case directedStudy
	case subjectPeriod

	init(from decoder: any Decoder) throws {
		if let value = try? decoder.singleValueContainer().decode(String.self),
		   let location = Self(rawValue: value)
		{
			self = location
			return
		}

		let container = try decoder.container(keyedBy: LegacyCodingKeys.self)
		if container.contains(.exam) {
			self = .exam
		} else if container.contains(.directedStudy) {
			self = .directedStudy
		} else if container.contains(.subjectPeriod) {
			self = .subjectPeriod
		} else {
			throw DecodingError.dataCorrupted(
				.init(
					codingPath: decoder.codingPath,
					debugDescription: "Unknown grade assessment location."
				)
			)
		}
	}

	private enum LegacyCodingKeys: String, CodingKey {
		case exam
		case directedStudy
		case subjectPeriod
	}
}

struct GradeTrackerDate: Codable, Hashable, Sendable {
	let year: Int
	let month: Int
	let day: Int
}

struct GradeAssessment: Codable, Hashable, Sendable {
	let id: UUID
	let subjectID: String
	let semester: Int
	let name: String
	let date: GradeTrackerDate
	let score: Double
	let weighting: Double
	let location: GradeAssessmentLocation
}

struct GradeTrackerDocument: Codable, Hashable, Sendable {
	var assessments: [GradeAssessment]
	var predictedATAR: Double?
	var goalATAR: Double?
	var serverRevision: Int

	static let empty = GradeTrackerDocument(
		assessments: [],
		predictedATAR: nil,
		goalATAR: nil,
		serverRevision: 0
	)
}

struct GradeTrackerUpdateRequest: Content {
	let document: GradeTrackerDocument
	let serverRevision: Int?
}

struct GradeTrackerResponse: Content {
	let document: GradeTrackerDocument
}
