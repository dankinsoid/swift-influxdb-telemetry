import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class FloatingCounter: InfluxMetric, FloatingPointCounterHandler {

	var id: HandlerID { handler.id }
	let handler: InfluxMetricHandler<Double>
    let coldStart: Bool
    let dimensions: [(String, String)]
    
    init(handler: InfluxMetricHandler<Double>, dimensions: [(String, String)], coldStart: Bool) {
        self.handler = handler
        self.coldStart = coldStart
        self.dimensions = dimensions
    }

	func increment(by amount: Double) {
        handler.modify(dimensions: dimensions, loadValues: !coldStart) {
			// We busy loop here until we can update the atomic successfully.
			// Using relaxed ordering here is sufficient, since the as-if rules guarantess that
			// the following operations are executed in the order presented here. Every statement
			// depends on the execution before.
			while true {
				let bits = $0.load(ordering: .relaxed)
				let value = Double(bitPattern: bits) + amount
				let (exchanged, _) = $0.compareExchange(
					expected: bits,
					desired: value.bitPattern,
					ordering: .relaxed
				)
				if exchanged {
					break
				}
			}
		}
	}

	func reset() {
        handler.modify(dimensions: dimensions) {
			$0.store(Double.zero.bitPattern, ordering: .relaxed)
		}
	}
}

extension FloatingCounter: MeterHandler {

	func set(_ value: Int64) {
		set(Double(value))
	}

	func set(_ value: Double) {
        handler.modify(dimensions: dimensions) {
			$0.store(value.bitPattern, ordering: .relaxed)
		}
	}

	func decrement(by amount: Double) {
		increment(by: -amount)
	}
}

extension FloatingCounter: RecorderHandler {

	func record(_ value: Int64) {
		set(value)
	}

	func record(_ value: Double) {
		set(value)
	}
}
