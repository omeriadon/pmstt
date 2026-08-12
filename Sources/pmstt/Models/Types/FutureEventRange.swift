import Vapor

enum FutureEventRange: String, Content, CaseIterable, Hashable {
	case oneWeek
	case twoWeeks
	case oneMonth
	case twoMonths
	case threeMonths
	case endOfYear
}
