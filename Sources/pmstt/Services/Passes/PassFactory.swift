import Crypto
import Fluent
import Foundation
import Vapor

enum PassFactory {
	static func response(for timetable: ResolvedTimetable, req: Request) async throws -> Response {
		let serial = try timetable.serialNumber
		let token = authenticationToken(serial: serial)
		let record = try await upsertRecord(for: timetable, token: token, on: req.db)
		return try await response(serial: serial, displayName: timetable.title, subjectsData: timetable.subjectsData, token: token, isDeleted: record.isDeleted, issuerAccountID: try timetable.author.requireID().uuidString, sourceKind: timetable.sourceKind, authorDisplayName: timetable.author.displayName, isShareable: timetable.isSearchable, req: req)
	}

	static func deletedResponse(record: PassRecord, req: Request) async throws -> Response {
		let empty = try JSONEncoder().encode([TimetableSubjectDTO]())
		return try await response(serial: record.serialNumber, displayName: "Deleted Timetable", subjectsData: empty, token: authenticationToken(serial: record.serialNumber), isDeleted: true, issuerAccountID: record.issuerAccountID, sourceKind: record.sourceKind, authorDisplayName: nil, isShareable: false, req: req)
	}

	static func authenticationToken(serial: String) -> String {
		let secret = Environment.get("PASS_AUTHENTICATION_SECRET") ?? Environment.get("JWT_SECRET") ?? "pmstt-development-pass-secret"
		return SHA256.hash(data: Data("\(secret):\(serial)".utf8)).map { String(format: "%02x", $0) }.joined()
	}

	static func tokenHash(_ token: String) -> String {
		SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
	}

	private static func upsertRecord(for timetable: ResolvedTimetable, token: String, on database: any Database) async throws -> PassRecord {
		let serial = try timetable.serialNumber
		let record = try await PassRecord.query(on: database).filter(\.$serialNumber == serial).first()
			?? PassRecord(serialNumber: serial, issuerAccountID: try timetable.author.requireID().uuidString, sourceKind: timetable.sourceKind, authoredTimetableID: authoredID(timetable), revision: timetable.revision, authenticationTokenHash: tokenHash(token))
		record.issuerAccountID = try timetable.author.requireID().uuidString
		record.sourceKind = timetable.sourceKind
		record.revision = timetable.revision
		record.authenticationTokenHash = tokenHash(token)
		record.isDeleted = false
		try await record.save(on: database)
		return record
	}

	private static func authoredID(_ timetable: ResolvedTimetable) -> UUID? {
		guard case let .authored(value) = timetable else { return nil }
		return value.id
	}

	private static func response(serial: String, displayName: String, subjectsData: Data, token: String, isDeleted: Bool, issuerAccountID: String, sourceKind: SourceKind, authorDisplayName: String?, isShareable: Bool, req: Request) async throws -> Response {
		let workingDir = req.application.directory.workingDirectory
		let resources = URL(fileURLWithPath: workingDir).appendingPathComponent("Sources/pmstt/Services/Passes")
		let fileURL = try await generatePass(serialNumber: serial, displayName: displayName, subjectsData: subjectsData, authenticationToken: token, webServiceURL: Environment.get("PASS_WEB_SERVICE_URL") ?? "https://timetable.adonis.pt/v1", isDeleted: isDeleted, issuerAccountID: issuerAccountID, sourceKind: sourceKind, authorDisplayName: authorDisplayName, isShareable: isShareable, resourceDirectory: resources)
		let data = try Data(contentsOf: fileURL)
		try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
		return Response(status: .ok, headers: ["Content-Type": "application/vnd.apple.pkpass", "Content-Disposition": "attachment; filename=\"timetable.pkpass\""], body: .init(data: data))
	}
}
