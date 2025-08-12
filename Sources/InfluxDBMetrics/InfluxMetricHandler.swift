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
	init(id: HandlerID, writer: InfluxDBPointsWriter, labelsAsTags: LabelsSet)
}

final class InfluxMetricHandler<Value: InfluxMetricValue>: AnyInfluxMetricHandler {
	
	let id: HandlerID
	private let atomic = ManagedAtomic(0 as Value.AsAtomic)
	private let writer: InfluxDBPointsWriter
	private let uuid = UUID()
	private let labelsAsTags: LabelsSet
	
	init(
		id: HandlerID,
		writer: InfluxDBPointsWriter,
		labelsAsTags: LabelsSet
	) {
		self.writer = writer
		self.id = id
		self.labelsAsTags = labelsAsTags
	}
	
	deinit {
		writer.close(measurementID: uuid)
	}
	
	func modify(
		dimensions: [(String, String)],
		_ operation: @Sendable @escaping (ManagedAtomic<Value.AsAtomic>) -> Void
	) {
		operation(self.atomic)
		self.write(dimensions: dimensions, date: Date())
	}

	private func write(dimensions: [(String, String)], date: Date) {
		writer.write(
			measurement: id.label,
			tags: [:],
			fields: ["value": Value.fieldValue(from: atomic.load(ordering: .relaxed))],
			unspecified: dimensions.map { ($0.0, .string($0.1)) },
			measurementID: uuid,
			telemetryType: "metrics",
			labelsAsTags: labelsAsTags,
			date: date
		)
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
