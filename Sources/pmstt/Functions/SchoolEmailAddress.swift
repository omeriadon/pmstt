import Vapor

func normalizedEmail(_ value: String) throws -> String {
	let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
	let components = email.split(separator: "@", omittingEmptySubsequences: false)

	guard
		email.count <= 254,
		components.count == 2,
		!components[0].isEmpty,
		!components[1].isEmpty,
		components[1].contains("."),
		!components[1].hasPrefix("."),
		!components[1].hasSuffix("."),
		!email.contains(where: \.isWhitespace)
	else {
		throw AppError(.badRequest, code: .invalidRequest, reason: "Enter a valid email address.", field: "email")
	}

	return email
}

func normalizedSchoolEmail(_ value: String) throws -> String {
	let email = try normalizedEmail(value)
	let suffix = "@student.education.wa.edu.au"

	guard email.hasSuffix(suffix) else {
		throw AppError(.badRequest, code: .invalidRequest, reason: "Use your school email address.", field: "email")
	}

	let localPart = email.dropLast(suffix.count)
	let names = localPart.split(separator: ".", omittingEmptySubsequences: false)
	guard names.count == 2,
	      !names[0].isEmpty,
	      !String(names[1]).trimmingCharacters(in: .decimalDigits).isEmpty
	else {
		throw AppError(.badRequest, code: .invalidRequest, reason: "Your school email must use the firstname.lastname format.", field: "email")
	}

	return email
}
