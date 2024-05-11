import Foundation

protocol InfluxMetric: Sendable {
	var id: HandlerID { get }
}
