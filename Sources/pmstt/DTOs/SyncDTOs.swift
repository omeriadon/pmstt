import Foundation
import Vapor

enum SyncRecordType: String, Content {
	case ownerTimetable
}

enum SyncMutationOperation: String, Content {
	case upsert
	case delete
}

enum SyncMutationOutcome: String, Content {
	case accepted
	case serverRecordNewer
	case deletedOnServer
	case invalidReferenceDropped
	case authorizationRejected
	case validationRejected
}

struct OwnerTimetableSyncPayload: Content {
	let subjects: [TimetableSubjectDTO]
	let isSearchable: Bool
}

struct SyncRecordMutation: Content {
	let mutationID: UUID
	let recordType: SyncRecordType
	let recordID: UUID?
	let operation: SyncMutationOperation
	let baseRevision: Int
	let ownerTimetable: OwnerTimetableSyncPayload?
}

struct SyncEnvelopeRequest: Content {
	let requestID: UUID
	let installationID: String
	let mutations: [SyncRecordMutation]
	let cursor: String?
}

struct SyncMutationResult: Content {
	let mutationID: UUID
	let recordType: SyncRecordType
	let recordID: UUID?
	let outcome: SyncMutationOutcome
	let serverRevision: Int
	let ownerTimetable: OwnerTimetableResponse?
	let droppedReferenceIDs: [UUID]
	let message: String?
}

struct SyncTombstone: Content {
	let recordType: SyncRecordType
	let recordID: UUID
	let revision: Int
	let deletedAt: Date
}

struct SyncEnvelopeResponse: Content {
	let serverTime: Date
	let requestID: UUID
	let installationID: String
	let results: [SyncMutationResult]
	let tombstones: [SyncTombstone]
	let nextCursor: String?
}
