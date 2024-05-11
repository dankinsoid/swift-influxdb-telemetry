import Foundation

public enum IntervalType: Hashable, Codable, Sendable {

	case regular(seconds: TimeInterval)
	case irregular
}
