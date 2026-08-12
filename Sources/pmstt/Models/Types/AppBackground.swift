import Vapor

enum AppBackground: String, Content, CaseIterable, Hashable {
	case blackPaper
	case grayPaper
	case brownPaper
	case solid
	case systemGray
	case dome
	case peak
	case tree
	case valley
}
