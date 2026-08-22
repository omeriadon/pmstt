import Vapor

func normalizedEmail(_ value: String) throws -> String {
	let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
	let components = email.split(separator: "@", omittingEmptySubsequences: false)

	guard
		email.count <= 100,
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
