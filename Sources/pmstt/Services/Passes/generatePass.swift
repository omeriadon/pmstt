import Crypto
import Foundation
import ZIPFoundation

enum PassError: Error {
	case templateNotFound
	case invalidJSON
	case signingFailed
	case zipFailed
}

private func Print(_ message: String) {
	print(message)
}

private func PrintError(_ message: String) {
	print("ERROR: \(message)")
}

func generatePass(
	serialNumber: String,
	displayName: String,
	subjectsData: Data,
	authenticationToken: String,
	webServiceURL: String,
	isDeleted: Bool = false,
	issuerAccountID: String? = nil,
	sourceKind: SourceKind = .accountOwner,
	authorDisplayName: String? = nil,
	isShareable: Bool = false,
	contentRevision: Int = 0,
	resourceDirectory: URL
) async throws -> URL {
	let startTime = ContinuousClock.now
	let fileManager = FileManager.default

	// 1. Locate the .pkpasstemplate in your resource directory
	let templateURL = resourceDirectory.appendingPathComponent("Shared Timetable.pkpasstemplate")
	guard fileManager.fileExists(atPath: templateURL.path) else {
		throw PassError.templateNotFound
	}

	// 2. Set up a temporary working directory
	let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	let passWorkingURL = tempDir.appendingPathComponent("Timetable Pass.pass")
	try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
	try fileManager.copyItem(at: templateURL, to: passWorkingURL)

	// 3. Read and parse pass.json
	let passJSONURL = passWorkingURL.appendingPathComponent("pass.json")
	let rawData = try Data(contentsOf: passJSONURL)

	guard var passDict = try JSONSerialization.jsonObject(with: rawData, options: []) as? [String: Any] else {
		throw PassError.invalidJSON
	}

	// MARK: - Encode data

	let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: subjectsData)
	let subjectsArray = try JSONSerialization.jsonObject(with: subjectsData, options: []) as? [[String: Any]] ?? []

	var userInfo = passDict["userInfo"] as? [String: Any] ?? [String: Any]()
	if let jsonString = String(data: subjectsData, encoding: .utf8) {
		userInfo["rawTimetableData"] = jsonString
	}
	passDict["userInfo"] = userInfo

	passDict["serialNumber"] = serialNumber
	passDict["authenticationToken"] = authenticationToken
	passDict["webServiceURL"] = webServiceURL
	userInfo["isDeleted"] = isDeleted
	userInfo["issuerAccountID"] = issuerAccountID
	userInfo["sourceKind"] = sourceKind.rawValue
	userInfo["authorDisplayName"] = authorDisplayName
	userInfo["isShareable"] = isShareable
	userInfo["contentRevision"] = contentRevision
	userInfo["passUpdatedAt"] = ISO8601DateFormatter().string(from: Date())
	passDict["userInfo"] = userInfo

	let dateFormatter = ISO8601DateFormatter()
	dateFormatter.formatOptions = [.withInternetDateTime]
	let sharedDate = dateFormatter.string(from: Date())

	for passType in ["generic", "posterGeneric"] {
		if var subField = passDict[passType] as? [String: Any] {
			if var primaryFields = subField["primaryFields"] as? [[String: Any]] {
				for index in primaryFields.indices {
					if let key = primaryFields[index]["key"] as? String {
						if key == "name" {
							primaryFields[index]["value"] = "\(displayName)'s Timetable"
						} else if key == "shared" {
							primaryFields[index]["value"] = sharedDate
						}
					}
				}
				subField["primaryFields"] = primaryFields
			}

			var currentBackFields = subField["backFields"] as? [[String: Any]] ?? [[String: Any]]()

			let subjectBackFields: [[String: Any]] = subjects.map { subject in
				return [
					"key": subject.id,
					"label": subject.id,
					"value": "\(subject.classroom.displayName)\n\(subject.teacher.displayName)\n\(subject.slots.count) slots"
				]
			}

			let subjectsSummaryString = subjectsArray
				.compactMap { $0["id"] as? String }
				.joined(separator: ", ")

			let subjectsSummaryItem: [String: Any] = [
				"key": "subjectsSummary",
				"label": "Subjects Summary",
				"value": subjectsSummaryString
			]

			let contextBackFields: [[String: Any]] = [
				[
					"key": "sender",
					"label": "Sender",
					"value": displayName
				],
				[
					"key": "shared",
					"label": "Shared On",
					"value": sharedDate,
					"dateStyle": "PKDateStyleLong",
					"timeStyle": "PKDateStyleNone"
				]
			] + subjectBackFields + [
				[
					"key": "amountOfSubjects",
					"label": "Total Subjects",
					"value": subjectsArray.count
				],
				subjectsSummaryItem
			]

			let newKeys = contextBackFields.compactMap { $0["key"] as? String }
			currentBackFields.removeAll { field in
				guard let key = field["key"] as? String else { return false }
				return newKeys.contains(key)
			}

			currentBackFields.append(contentsOf: contextBackFields)
			subField["backFields"] = currentBackFields

			if var footerFields = subField["footerFields"] as? [[String: Any]] {
				var updated = false

				for index in footerFields.indices {
					if let key = footerFields[index]["key"] as? String, key == "subjectsSummary" {
						footerFields[index]["value"] = subjectsSummaryString
						updated = true
					}
				}

				if !updated {
					footerFields.append([
						"key": "subjectsSummary",
						"label": "Subjects Summary",
						"textAlignment": "PKTextAlignmentNatural",
						"value": subjectsSummaryString
					])
				}

				subField["footerFields"] = footerFields
			} else {
				subField["footerFields"] = [[
					"key": "subjectsSummary",
					"label": "Subjects Summary",
					"textAlignment": "PKTextAlignmentNatural",
					"value": subjectsSummaryString
				]]
			}

			passDict[passType] = subField
		}
	}

	let modifiedJSONData = try JSONSerialization.data(withJSONObject: passDict, options: .prettyPrinted)
	try modifiedJSONData.write(to: passJSONURL)

	let toolingURL = passWorkingURL.appendingPathComponent("tooling.json")
	try? fileManager.removeItem(at: toolingURL)

	// 4. Generate manifest.json
	var manifest = [String: String]()
	let files = try fileManager.contentsOfDirectory(atPath: passWorkingURL.path)

	for file in files {
		guard file != ".DS_Store", file != "manifest.json", file != "signature" else { continue }

		let fileURL = passWorkingURL.appendingPathComponent(file)

		var isDirectory: ObjCBool = false
		if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
			continue
		}

		let fileData = try Data(contentsOf: fileURL)
		let hash = Insecure.SHA1.hash(data: fileData)
		let hashString = hash.map { String(format: "%02x", $0) }.joined()
		manifest[file] = hashString
	}

	let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
	let manifestURL = passWorkingURL.appendingPathComponent("manifest.json")
	try manifestData.write(to: manifestURL)

	// 5. Sign the manifest using system OpenSSL
	let signatureURL = passWorkingURL.appendingPathComponent("signature")

	do {
		try signManifestWithBundledKey(
			manifestURL: manifestURL,
			outputSignatureURL: signatureURL,
			resourceDirectory: resourceDirectory
		)
	} catch {
		PrintError("Cryptographic signing failed: \(error)")
		throw PassError.signingFailed
	}

	// 6. Compress everything into a .pkpass file
	let finalPkpassURL = tempDir.appendingPathComponent("Timetable.pkpass")

	do {
		try fileManager.zipItem(
			at: passWorkingURL,
			to: finalPkpassURL,
			shouldKeepParent: false
		)

		let elapsedTime = ContinuousClock.now - startTime
		Print("Pass generation took: \(elapsedTime)")
		return finalPkpassURL
	} catch {
		PrintError("Zipping up your .pkpass archive failed: \(error)")
		throw PassError.zipFailed
	}
}
