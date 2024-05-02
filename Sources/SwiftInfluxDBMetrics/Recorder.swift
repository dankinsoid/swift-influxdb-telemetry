import Atomics
import CoreMetrics
import InfluxDBSwift
import SwiftInfluxDBCore

final class AggregateRecorder: InfluxMetric, RecorderHandler {

    var id: HandlerID { handler.id }
    let handler: InfluxMetricHandler<UInt64>
    private let counter = ManagedAtomic<Int>(0)

    init(api: SwiftInfluxAPI, id: HandlerID, fields: [(String, String)]) {
        handler = InfluxMetricHandler(id: id, fields: fields, api: api) {
            .double(Double(bitPattern: $0))
        }
    }

    func record(_ value: Int64) {
        record(Double(value))
    }

    func record(_ value: Double) {
        counter.wrappingIncrement(by: 1, ordering: .relaxed)
        handler.modify(additional: ["\(handler.id.type)_count": .int(counter.load(ordering: .relaxed))]) {
            $0.store(value.bitPattern, ordering: .relaxed)
        }
    }
}
