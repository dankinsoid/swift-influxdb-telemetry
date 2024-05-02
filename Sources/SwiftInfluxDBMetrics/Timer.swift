import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class TimerMetric: InfluxMetric, TimerHandler {

    var id: HandlerID { handler.id }
    let handler: InfluxMetricHandler<Int>

    init(api: SwiftInfluxAPI, id: HandlerID, fields: [(String, String)]) {
        handler = InfluxMetricHandler(id: id, fields: fields, api: api) {
            .int($0)
        }
    }

    func recordNanoseconds(_ duration: Int64) {
        handler.modify {
            $0.wrappingIncrement(by: Int(duration), ordering: .relaxed)
        }
    }
}
