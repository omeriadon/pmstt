import Foundation

enum AccountAuthority: String, Codable, CaseIterable, Sendable {
	case user
	case administrator
	case systemOwner

	static let systemOwnerEmails: Set<String> = [
		"omeriadon@outlook.com",
		"adon.omeri@student.education.wa.edu.au",
	]

	static func resolved(for email: String?, storedAuthority: AccountAuthority) -> AccountAuthority {
		guard let email else {
			return storedAuthority
		}

		let normalizedEmail = email
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()

		if systemOwnerEmails.contains(normalizedEmail) {
			return .systemOwner
		}

		return storedAuthority
	}
}
