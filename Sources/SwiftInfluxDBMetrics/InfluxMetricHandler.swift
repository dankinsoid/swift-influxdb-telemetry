import Atomics
import InfluxDBSwift
import SwiftInfluxDBCore

struct InfluxMetricHandler<Value: AtomicValue & ExpressibleByIntegerLiteral & Sendable>: Sendable where Value.AtomicRepresentation.Value == Value {

    let id: HandlerID
    private let fields: [(String, String)]
    private let atomic = ManagedAtomic(0 as Value)
    private let api: SwiftInfluxAPI
    private let value: @Sendable (Value.AtomicRepresentation.Value) -> InfluxDBClient.Point.FieldValue

    init(
        id: HandlerID,
        fields: [(String, String)],
        api: SwiftInfluxAPI,
        value: @Sendable @escaping (Value.AtomicRepresentation.Value) -> InfluxDBClient.Point.FieldValue
    ) {
        self.api = api
        self.id = id
        self.value = value
        self.fields = fields
    }

    func modify(additional: [String: InfluxDBClient.Point.FieldValue] = [:], _ operation: (ManagedAtomic<Value>) -> Void) {
        operation(atomic)
        var fields = Dictionary(self.fields) { _, n in n }.mapValues(InfluxDBClient.Point.FieldValue.string)
        fields.merge(additional) { _, new in new }
        fields[id.type] = value(atomic.load(ordering: .relaxed))
        api.write(
            measurement: id.label,
            tags: id.tags,
            fields: fields,
            unspecified: []
        )
    }
}
