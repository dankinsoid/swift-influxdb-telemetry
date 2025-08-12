import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class Counter: InfluxMetric, CounterHandler {
	
	var id: HandlerID { handler.id }
	let handler: InfluxMetricHandler<Int>
	let dimensions: [(String, String)]
	
	init(handler: InfluxMetricHandler<Int>, dimensions: [(String, String)]) {
		self.handler = handler
		self.dimensions = dimensions
	}
	
	func increment(by amount: Int64) {
		handler.modify(dimensions: dimensions) {
			$0.wrappingIncrement(by: Int(amount), ordering: .relaxed)
		}
	}
	
	func reset() {
		handler.modify(dimensions: dimensions) {
			$0.store(0, ordering: .relaxed)
		}
	}
}
