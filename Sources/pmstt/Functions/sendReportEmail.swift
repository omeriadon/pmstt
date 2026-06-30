//
//  sendReportEmail.swift
//  pmstt
//
//  Created by Adon Omeri on 28/6/2026.
//

import Fluent
import Vapor

let resendAPIKey = "re_GSwEFAdz_H52TxxRZbeNekpR5me3Bkizn"

struct ResendEmailRequest: Content {
	let from: String
	let to: String
	let subject: String
	let html: String
}

func sendReportEmail(
	body: ReportUserRequest,
	reporterUser: User,
	reportedUser: User,
	req: Request
) async throws -> Response {
	let reportedUserID = try reportedUser.requireID()

	let ownerTimetable: OwnerTimetable? = try await OwnerTimetable.query(on: req.db)
		.filter(\.$user.$id == reportedUserID)
		.first()

	let authoredTimetables: [AuthoredTimetable] = try await AuthoredTimetable.query(on: req.db)
		.filter(\.$author.$id == reportedUserID)
		.all()

	let html = """
	<h1>Timetable App User Report</h1>

	<h2>Report Metadata</h2>
	<ul>
	 <li><strong>Reported Account ID from Request:</strong> \(escapeHTML(body.reportedAccountID))</li>
	 <li><strong>Generated At:</strong> \(Date().description)</li>
	</ul>

	\(renderUserHTML(title: "Reporter", user: reporterUser))

	\(renderUserHTML(title: "Reported User", user: reportedUser))

	<h2>Reported User Timetables</h2>

	\(renderOwnerTimetableHTML(ownerTimetable))

	\(renderAuthoredTimetablesHTML(authoredTimetables))
	"""

	let email = ResendEmailRequest(
		from: "onboarding@resend.dev",
		to: "adon.omeri@student.education.wa.edu.au",
		subject: "Timetable App User Report",
		html: html
	)

	let response = try await req.client.post(
		URI(string: "https://api.resend.com/emails"),
		headers: [
			"Authorization": "Bearer \(resendAPIKey)",
			"Content-Type": "application/json"
		]
	) { clientReq in
		try clientReq.content.encode(email)
	}

	guard response.status == HTTPStatus.ok || response.status == HTTPStatus.created else {
		let responseBody = response.body.map { buffer in
			String(buffer: buffer)
		} ?? "No response body"

		req.logger.error("Resend email failed with status \(response.status): \(responseBody)")

		throw Abort(.badGateway, reason: "Email failed to send.")
	}

	return Response(status: .created)
}

// MARK: - HTML Rendering

private func renderUserHTML(title: String, user: User) -> String {
	"""
	<h2>\(escapeHTML(title))</h2>
	<table border="1" cellpadding="6" cellspacing="0">
	 <tr>
	  <th align="left">Field</th>
	  <th align="left">Value</th>
	 </tr>
	 <tr>
	  <td>ID</td>
	  <td>\(escapeHTML(user.id?.uuidString ?? "nil"))</td>
	 </tr>
	 <tr>
	  <td>Email</td>
	  <td>\(escapeHTML(user.email ?? "nil"))</td>
	 </tr>
	 <tr>
	  <td>Display Name</td>
	  <td>\(escapeHTML(user.displayName))</td>
	 </tr>
	 <tr>
	  <td>Self Pass Serial Number</td>
	  <td>\(escapeHTML(user.selfPassSerialNumber))</td>
	 </tr>
	 <tr>
	  <td>Created At</td>
	  <td>\(escapeHTML(user.createdAt?.description ?? "nil"))</td>
	 </tr>
	 <tr>
	  <td>Updated At</td>
	  <td>\(escapeHTML(user.updatedAt?.description ?? "nil"))</td>
	 </tr>
	</table>
	"""
}

private func renderOwnerTimetableHTML(_ timetable: OwnerTimetable?) -> String {
	guard let timetable else {
		return """
		<h3>Own Timetable</h3>
		<p><em>No own timetable found.</em></p>
		"""
	}

	return """
	<h3>Own Timetable</h3>
	<table border="1" cellpadding="6" cellspacing="0">
	 <tr>
	  <th align="left">Field</th>
	  <th align="left">Value</th>
	 </tr>
	 <tr>
	  <td>ID</td>
	  <td>\(escapeHTML(timetable.id?.uuidString ?? "nil"))</td>
	 </tr>
	 <tr>
	  <td>Revision</td>
	  <td>\(timetable.revision)</td>
	 </tr>
	 <tr>
	  <td>Created At</td>
	  <td>\(escapeHTML(timetable.createdAt?.description ?? "nil"))</td>
	 </tr>
	 <tr>
	  <td>Updated At</td>
	  <td>\(escapeHTML(timetable.updatedAt?.description ?? "nil"))</td>
	 </tr>
	</table>

	<h4>Own Timetable Subjects</h4>
	\(renderSubjectsHTML(timetable.subjectsData))
	"""
}

private func renderAuthoredTimetablesHTML(_ timetables: [AuthoredTimetable]) -> String {
	guard !timetables.isEmpty else {
		return """
		<h3>Authored Timetables</h3>
		<p><em>No authored timetables found.</em></p>
		"""
	}

	let items = timetables.map { timetable in
		"""
		<div style="border: 1px solid #999; padding: 12px; margin: 12px 0;">
		 <h4>Authored Timetable</h4>

		 <table border="1" cellpadding="6" cellspacing="0">
		  <tr>
		   <th align="left">Field</th>
		   <th align="left">Value</th>
		  </tr>
		  <tr>
		   <td>ID</td>
		   <td>\(escapeHTML(timetable.id?.uuidString ?? "nil"))</td>
		  </tr>
		  <tr>
		   <td>Subject Display Name</td>
		   <td>\(escapeHTML(timetable.subjectDisplayName))</td>
		  </tr>
		  <tr>
		   <td>Pass Serial Number</td>
		   <td>\(escapeHTML(timetable.passSerialNumber))</td>
		  </tr>
		  <tr>
		   <td>Revision</td>
		   <td>\(timetable.revision)</td>
		  </tr>
		  <tr>
		   <td>Is Deleted</td>
		   <td>false</td>
		  </tr>
		  <tr>
		   <td>Created At</td>
		   <td>\(escapeHTML(timetable.createdAt?.description ?? "nil"))</td>
		  </tr>
		  <tr>
		   <td>Updated At</td>
		   <td>\(escapeHTML(timetable.updatedAt?.description ?? "nil"))</td>
		  </tr>
		 </table>

		 <h5>Subjects</h5>
		 \(renderSubjectsHTML(timetable.subjectsData))
		</div>
		"""
	}.joined(separator: "\n")

	return """
	<h3>Authored Timetables</h3>
	\(items)
	"""
}

private func renderSubjectsHTML(_ data: Data) -> String {
	do {
		let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: data)

		guard !subjects.isEmpty else {
			return "<p><em>No subjects.</em></p>"
		}

		return subjects.enumerated().map { index, subject in
			let slotsHTML = subject.slots.enumerated().map { slotIndex, slot in
				"""
				<li>
				 <strong>Slot \(slotIndex + 1)</strong>
				 <ul>
				  <li>Day: \(slot.day)</li>
				  <li>Session: \(slot.session)</li>
				 </ul>
				</li>
				"""
			}.joined(separator: "\n")

			return """
			<div style="border: 1px solid #ccc; padding: 8px; margin: 8px 0;">
			 <h5>Subject \(index + 1)</h5>

			 <table border="1" cellpadding="6" cellspacing="0">
			  <tr>
			   <th align="left">Field</th>
			   <th align="left">Value</th>
			  </tr>
			  <tr>
			   <td>ID</td>
			   <td>\(escapeHTML(subject.id))</td>
			  </tr>
			  <tr>
			   <td>Symbol</td>
			   <td>\(escapeHTML(subject.symbol))</td>
			  </tr>
			  <tr>
			   <td>Colour Red</td>
			   <td>\(subject.colour.r)</td>
			  </tr>
			  <tr>
			   <td>Colour Green</td>
			   <td>\(subject.colour.g)</td>
			  </tr>
			  <tr>
			   <td>Colour Blue</td>
			   <td>\(subject.colour.b)</td>
			  </tr>
			  <tr>
			   <td>Colour Alpha</td>
			   <td>\(subject.colour.a)</td>
			  </tr>
			 </table>

			 <h6>Slots</h6>
			 <ul>
			  \(slotsHTML)
			 </ul>
			</div>
			"""
		}.joined(separator: "\n")
	} catch {
		return """
		<p>
		 <strong>Failed to decode subjectsData:</strong>
		 \(escapeHTML(String(describing: error)))
		</p>
		"""
	}
}

private func escapeHTML(_ value: String) -> String {
	value
		.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "<", with: "&lt;")
		.replacingOccurrences(of: ">", with: "&gt;")
		.replacingOccurrences(of: "\"", with: "&quot;")
		.replacingOccurrences(of: "'", with: "&#39;")
}
