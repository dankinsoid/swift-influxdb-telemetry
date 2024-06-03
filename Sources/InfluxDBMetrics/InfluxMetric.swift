import Foundation

protocol InfluxMetric<Handler>: Sendable {

    associatedtype Handler: AnyInfluxMetricHandler
	var id: HandlerID { get }
    init(handler: Handler, dimensions: [(String, String)], coldStart: Bool)
}
