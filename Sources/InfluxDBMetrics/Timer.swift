import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class TimerMetric: InfluxMetric, TimerHandler {

	var id: HandlerID { handler.id }
	let handler: InfluxMetricHandler<Int>
    let dimensions: [(String, String)]
    
    init(handler: InfluxMetricHandler<Int>, dimensions: [(String, String)]) {
        self.handler = handler
        self.dimensions = dimensions
    }

	func recordNanoseconds(_ duration: Int64) {
        handler.modify(dimensions: dimensions) {
			$0.store(Int(duration), ordering: .relaxed)
		}
	}
}
