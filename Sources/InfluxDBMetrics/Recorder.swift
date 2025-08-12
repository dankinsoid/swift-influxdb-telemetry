import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class AggregateRecorder: InfluxMetric, RecorderHandler {

	var id: HandlerID { handler.id }
	let handler: InfluxMetricHandler<Double>
    let counter: CoreMetrics.Counter
    let dimensions: [(String, String)]

    init(handler: InfluxMetricHandler<Double>, dimensions: [(String, String)]) {
        self.handler = handler
        self.dimensions = dimensions
        counter = CoreMetrics.Counter(label: handler.id.label + "_total", dimensions: dimensions)
    }

	func record(_ value: Int64) {
		record(Double(value))
	}

	func record(_ value: Double) {
        counter.increment()
        handler.modify(dimensions: dimensions) {
			$0.store(value.bitPattern, ordering: .relaxed)
		}
	}
}
