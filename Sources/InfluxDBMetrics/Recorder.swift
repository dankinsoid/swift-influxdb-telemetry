import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class AggregateRecorder: InfluxMetric, RecorderHandler {

	var id: HandlerID { handler.id }
	let handler: InfluxMetricHandler<UInt64>
	let countHandler: InfluxMetricHandler<Int>
    let coldStart: Bool

	init(api: InfluxDBWriter, id: HandlerID, fields: [(String, String)], coldStart: Bool) {
		handler = InfluxMetricHandler(id: id, fields: fields, api: api) {
			.double(Double(bitPattern: $0))
		}
		var counterID = id
		counterID.label += "_total"
		countHandler = InfluxMetricHandler(id: counterID, fields: fields, api: api) {
			.int($0)
		}
        self.coldStart = coldStart
	}

	func record(_ value: Int64) {
		record(Double(value))
	}

	func record(_ value: Double) {
		countHandler.modify(loadValues: !coldStart) {
			$0.wrappingDecrement(by: 1, ordering: .relaxed)
		}
		handler.modify {
			$0.store(value.bitPattern, ordering: .relaxed)
		}
	}
}
