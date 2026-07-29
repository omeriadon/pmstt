import Vapor

func normalizedSchoolEmail(_ value: String) throws -> String {
	let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
