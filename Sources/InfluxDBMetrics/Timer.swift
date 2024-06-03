import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class TimerMetric: InfluxMetric, TimerHandler {

	var id: HandlerID { handler.id }
	let handler: InfluxMetricHandler<Int>
    let dimensions: [(String, String)]
    let coldStart: Bool
    
    init(handler: InfluxMetricHandler<Int>, dimensions: [(String, String)], coldStart: Bool) {
        self.handler = handler
        self.coldStart = coldStart
        self.dimensions = dimensions
    }

	func recordNanoseconds(_ duration: Int64) {
        handler.modify(dimensions: dimensions) {
			$0.store(Int(duration), ordering: .relaxed)
		}
	}
}
