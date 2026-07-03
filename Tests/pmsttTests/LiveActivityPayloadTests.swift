import Foundation
@testable import pmstt
import Testing

@Suite("Live Activity APNs payload")
struct LiveActivityPayloadTests {
	@Test("Start payload uses ActivityKit wire keys and default Date encoding")
	func startPayloadEncoding() throws {
		let start = Date(timeIntervalSinceReferenceDate: 100)
		let end = Date(timeIntervalSinceReferenceDate: 200)
		let state = SchoolDayActivityContentState(
			phase: .lesson,
			title: "Maths",
			symbol: "function",
			color: .blue,
			nextText: "Next: English",
			startDate: start,
			endDate: end
		)
		let payload = LiveActivityPayload(aps: .init(
			timestamp: 1_700_000_000,
			event: .start,
			contentState: state,
			staleDate: 1_700_000_300,
			dismissalDate: nil,
			attributesType: "SchoolDayActivityAttributes",
			attributes: .init(activityKey: UUID().uuidString, schoolDate: "2026-07-03"),
			inputPushToken: 1,
			alert: .init(title: "School day", body: "Maths")
		))

		let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
		let aps = try #require(object["aps"] as? [String: Any])
		let content = try #require(aps["content-state"] as? [String: Any])
		#expect(aps["event"] as? String == "start")
		#expect(aps["attributes-type"] as? String == "SchoolDayActivityAttributes")
		#expect(aps["input-push-token"] as? Int == 1)
		#expect(content["phase"] as? String == "lesson")
		#expect(content["startDate"] as? Double == 100)
		#expect(content["endDate"] as? Double == 200)
	}
}
