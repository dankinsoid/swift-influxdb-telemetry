import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class Counter: InfluxMetric, CounterHandler {

    var id: HandlerID { handler.id }
    let handler: InfluxMetricHandler<Int>

    init(api: SwiftInfluxAPI, id: HandlerID, fields: [(String, String)]) {
        handler = InfluxMetricHandler(id: id, fields: fields, api: api) {
            .int($0)
        }
    }

    func increment(by amount: Int64) {
        handler.modify {
            $0.wrappingIncrement(by: Int(amount), ordering: .relaxed)
        }
    }

    func reset() {
        handler.modify {
            $0.store(0, ordering: .relaxed)
        }
    }
}
