import Atomics
import Foundation
import InfluxDBSwift
import SwiftInfluxDBCore

protocol InfluxMetricValue: Sendable where AsAtomic.AtomicRepresentation.Value == AsAtomic {

    associatedtype AsAtomic: AtomicValue & ExpressibleByIntegerLiteral & Sendable
    static func fieldValue(from value: AsAtomic.AtomicRepresentation.Value) -> InfluxDBClient.Point.FieldValue
    static func loaded(from decodable: Decodable) -> AsAtomic?
}

protocol AnyInfluxMetricHandler: Sendable {
    var id: HandlerID { get }
    init(id: HandlerID, api: InfluxDBWriter)
}

final class InfluxMetricHandler<Value: InfluxMetricValue>: AnyInfluxMetricHandler {

	let id: HandlerID
	private let didLoad = ManagedAtomic(false)
    private let atomic = ManagedAtomic(0 as Value.AsAtomic)
	private let intervalTask = NIOLockedValueBox<Task<Void, Error>?>(nil)
	private let query = NIOLockedValueBox([@Sendable (Bool) -> Void]())
	private let api: InfluxDBWriter
	private let uuid = UUID()

	init(
		id: HandlerID,
		api: InfluxDBWriter
	) {
		self.api = api
		self.id = id
	}

	deinit {
		api.close(measurementID: uuid)
	}

	func modify(
        dimensions: [(String, String)],
		loadValues: Bool = false,
        _ operation: @Sendable @escaping (ManagedAtomic<Value.AsAtomic>) -> Void
	) {
		let prependDate = Date()
		let date = Date()
		let writeOperation: @Sendable (Bool) -> Void = { [weak self] prependValue in
			guard let self else { return }
			if prependValue {
                self.write(dimensions: dimensions, date: prependDate)
			}
			operation(self.atomic)
            self.write(dimensions: dimensions, date: date)
		}
		let isLoading = !query.withLockedValue(\.isEmpty)
		if isLoading || loadValues && !didLoad.load(ordering: .sequentiallyConsistent) {
            addOperationToQueue(writeOperation)
		} else {
			writeOperation(false)
		}
	}

	private func write(dimensions: [(String, String)], date: Date) {
		api.write(
			measurement: id.label,
            tags: [:],
            fields: ["value": Value.fieldValue(from: atomic.load(ordering: .relaxed))],
            unspecified: dimensions.map { ($0.0, .string($0.1)) },
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
                let value = result.values["_value"].flatMap(Value.loaded)
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

extension Int: InfluxMetricValue {

    static func fieldValue(from value: Int) -> InfluxDBSwift.InfluxDBClient.Point.FieldValue {
        .int(value)
    }

    static func loaded(from decodable: any Decodable) -> Int? {
        if let int = decodable as? any FixedWidthInteger {
            return Int(int)
        }
        return nil
    }
}

extension Double: InfluxMetricValue {

    static func fieldValue(from value: UInt64) -> InfluxDBClient.Point.FieldValue {
        .double(Double(bitPattern: value))
    }

    static func loaded(from decodable: any Decodable) -> UInt64? {
        if let double = decodable as? any BinaryFloatingPoint {
            return Double(double).bitPattern
        }
        return nil
    }
}
