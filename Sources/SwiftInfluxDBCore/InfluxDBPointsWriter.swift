import Foundation

public protocol InfluxDBPointsWriter: Sendable {

	func write(point: InfluxDBClient.Point, measurementID: UUID)
	func close(measurementID: UUID)
}

package extension InfluxDBPointsWriter {
	
	func write(
		measurement: String,
		tags: [String: String],
		fields: [String: InfluxDBClient.Point.FieldValue],
		unspecified: [(String, InfluxDBClient.Point.FieldValue)],
		measurementID: UUID,
		telemetryType: String,
		labelsAsTags: LabelsSet,
		date: Date = Date()
	) {
		let point = InfluxDBClient.Point(measurement)
		point.time(time: .date(date))
		point.addTag(key: "telemetry_type", value: telemetryType)
		for (key, value) in unspecified {
			if labelsAsTags.contains(key, in: measurement) {
				point.addTag(key: key, value: value.string)
			} else {
				point.addField(key: key, value: value)
			}
		}
		for (key, value) in tags {
			point.addTag(key: key, value: value)
		}
		for (key, value) in fields {
			point.addField(key: key, value: value)
		}
		write(point: point, measurementID: measurementID)
	}
}
