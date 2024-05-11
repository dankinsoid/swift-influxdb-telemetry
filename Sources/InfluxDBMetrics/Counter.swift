import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class Counter: InfluxMetric, CounterHandler {

	var id: HandlerID { handler.id }
	let handler: InfluxMetricHandler<Int>

	init(api: InfluxDBWriter, id: HandlerID, fields: [(String, String)]) {
		handler = InfluxMetricHandler(id: id, fields: fields, api: api) {
			.int($0)
		} loaded: { decodable in
			if let int = decodable as? any FixedWidthInteger {
				return Int(int)
			}
			return nil
		}
	}

	func increment(by amount: Int64) {
		handler.modify(loadValues: true) {
			$0.wrappingIncrement(by: Int(amount), ordering: .relaxed)
		}
	}

	func reset() {
		handler.modify {
			$0.store(0, ordering: .relaxed)
		}
	}
}
