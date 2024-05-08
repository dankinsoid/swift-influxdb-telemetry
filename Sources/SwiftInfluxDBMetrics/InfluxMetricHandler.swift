import Atomics
import InfluxDBSwift
import SwiftInfluxDBCore

struct InfluxMetricHandler<Value: AtomicValue & ExpressibleByIntegerLiteral & Sendable>: Sendable where Value.AtomicRepresentation.Value == Value {

    let id: HandlerID
    private let fields: [(String, String)]
    private let didLoad = ManagedAtomic(false)
    private let atomic = ManagedAtomic(0 as Value)
    private let query = NIOLockedValueBox([@Sendable () -> Void]())
    private let api: InfluxDBWriter
    private let toValue: @Sendable (Decodable) -> Value?
    private let value: @Sendable (Value.AtomicRepresentation.Value) -> InfluxDBClient.Point.FieldValue

    init(
        id: HandlerID,
        fields: [(String, String)],
        api: InfluxDBWriter,
        value: @Sendable @escaping (Value.AtomicRepresentation.Value) -> InfluxDBClient.Point.FieldValue,
        loaded: @Sendable @escaping (Decodable) -> Value? = { _ in nil }
    ) {
        self.api = api
        self.id = id
        self.value = value
        self.fields = fields
        self.toValue = loaded
    }

    func modify(
        loadValues: Bool = false,
        additional: [String: InfluxDBClient.Point.FieldValue] = [:],
        _ operation: @Sendable @escaping (ManagedAtomic<Value>) -> Void
    ) {
        let writeOperation: @Sendable () -> Void = {
            operation(atomic)
            var fields = Dictionary(self.fields) { _, n in n }.mapValues(InfluxDBClient.Point.FieldValue.string)
            fields.merge(additional) { _, new in new }
            fields["value"] = value(atomic.load(ordering: .relaxed))
            api.write(
                measurement: id.label,
                tags: id.tags,
                fields: fields,
                unspecified: []
            )
        }
        let isLoading = !query.withLockedValue(\.isEmpty)
        if isLoading || loadValues && !didLoad.load(ordering: .sequentiallyConsistent) {
            addOperationToQueue(writeOperation)
        } else {
            writeOperation()
        }
    }
    
    private func addOperationToQueue(
        _ operation: @Sendable @escaping () -> Void
    ) {
        let needStart = query.withLockedValue {
            $0.append(operation)
            return $0.count == 1
        }
        if needStart {
            Task {
                await loadValue()
            }
        }
    }
    
    private func loadValue() async {
        do {
            if 
                let result = try await api.load(measurement: id.label, tags: id.tags, fields: ["value"]),
                let value = result.values["_value"].flatMap(toValue)
            {
                atomic.store(value, ordering: .sequentiallyConsistent)
            }
        } catch {
        }
        query.withLockedValue {
            for operation in $0 {
                operation()
            }
            $0 = []
        }
        didLoad.store(true, ordering: .sequentiallyConsistent)
    }
}
