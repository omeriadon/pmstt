import Foundation
import Vapor

enum GradeAssessmentLocation: String, Codable, Sendable {
	case exam
	case directedStudy
	case subjectPeriod
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
