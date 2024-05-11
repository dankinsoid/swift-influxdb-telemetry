import Atomics
import Foundation
import InfluxDBSwift
import SwiftInfluxDBCore

final class InfluxMetricHandler<Value: AtomicValue & ExpressibleByIntegerLiteral & Sendable>: Sendable where Value.AtomicRepresentation.Value == Value {

	let id: HandlerID
	private let fields: [(String, String)]
	private let didLoad = ManagedAtomic(false)
	private let atomic = ManagedAtomic(0 as Value)
	private let intervalTask = NIOLockedValueBox<Task<Void, Error>?>(nil)
	private let query = NIOLockedValueBox([@Sendable (Bool) -> Void]())
	private let api: InfluxDBWriter
	private let toValue: @Sendable (Decodable) -> Value?
	private let value: @Sendable (Value.AtomicRepresentation.Value) -> InfluxDBClient.Point.FieldValue
	private let uuid = UUID()

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
		toValue = loaded
	}

	deinit {
		api.close(measurementID: uuid)
	}

	func modify(
		loadValues: Bool = false,
		_ operation: @Sendable @escaping (ManagedAtomic<Value>) -> Void
	) {
        let prependDate = Date()
        let date = Date()
		let writeOperation: @Sendable (Bool) -> Void = { [weak self] prependValue in
			guard let self else { return }
            if prependValue {
                self.write(date: prependDate)
            }
			operation(self.atomic)
			self.write(date: date)
		}
		let isLoading = !query.withLockedValue(\.isEmpty)
		if isLoading || loadValues && !didLoad.load(ordering: .sequentiallyConsistent) {
			addOperationToQueue(writeOperation)
		} else {
			writeOperation(false)
		}
	}

    private func write(date: Date) {
		var fields = Dictionary(fields) { _, n in n }.mapValues(InfluxDBClient.Point.FieldValue.string)
		fields["value"] = value(atomic.load(ordering: .relaxed))
		api.write(
			measurement: id.label,
			tags: id.tags,
			fields: fields,
			unspecified: [],
			measurementID: uuid,
            date: date
		)
	}

	private func addOperationToQueue(
		_ operation: @Sendable @escaping (Bool) -> Void
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
        var needPrepend = false
		do {
			if
				let result = try await api.load(measurement: id.label, tags: id.tags, fields: ["value"]),
				let value = result.values["_value"].flatMap(toValue)
			{
				atomic.store(value, ordering: .sequentiallyConsistent)
            } else {
                needPrepend = true
            }
		} catch {}
		query.withLockedValue {
            for i in $0.indices {
                $0[i](needPrepend && i == 0)
			}
			$0 = []
		}
		didLoad.store(true, ordering: .sequentiallyConsistent)
	}
}
