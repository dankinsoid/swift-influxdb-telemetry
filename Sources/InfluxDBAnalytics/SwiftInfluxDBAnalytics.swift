import Foundation
@_exported import InfluxDBSwift
@_exported import SwiftAnalytics
@_exported import SwiftInfluxDBCore

/// InfluxDB Analytics Handler.
/// `InfluxDBAnalyticsHandler` constructs measurements for events, using the event's name as the measurement name.
/// Event parameters may either be stored as fields or tags, based on the `parametersLabelsAsTags` parameter.
/// Default parameters labels are defined in the `String.InfluxDBAnalyticsLabels` namespace as static constants.
///
/// Usage:
/// ```swift
/// AnalyticsSystem.bootstrap(
///     InfluxDBAnalyticsHandler(
///         url: "http://localhost:8086",
///         token: "your-token",
///         org: "your-org-name",
///         bucket: "your-bucket-name",
///         precision: .ms, // Optional
///         batchSize: 5000, // Optional
///         throttleInterval: 5, // Optional
///         parametersLabelsAsTags: LabelsSet.analyticsDefault.union([.InfluxDBAnalyticsLabels.file]) // Optional
///     )
/// )
/// ```
public struct InfluxDBAnalyticsHandler: AnalyticsHandler {

	public var parameters: Analytics.Parameters

	private let api: InfluxDBWriter
	private let uuid = UUID()
	private let measurementNamePolicy: MeasurementNamePolicy
	private let labelsAsTags: LabelsSet

	/// Create a new `InfluxDBAnalyticsHandler`.
	/// - Parameters:
	///   - options: The InfluxDB writer options.
	///   - measurementNamePolicy: Defines how to name the measurement. Defaults to `.byName`.
	///   - parametersLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "event_name"].
	///   - parameters: Global parameters for all events. Defaults to `[:]`.
	public init(
		options: BucketWriterOptions,
		measurementNamePolicy: MeasurementNamePolicy = .byName,
		parametersLabelsAsTags: LabelsSet = .analyticsDefault,
		parameters: Analytics.Parameters = [:]
	) {
		api = InfluxDBWriter(options: options)
		self.measurementNamePolicy = measurementNamePolicy
		self.parameters = parameters
		self.labelsAsTags = parametersLabelsAsTags
	}

	/// Create a new `InfluxDBAnalyticsHandler`.
	/// - Parameters:
	///   - url: InfluxDB host and port.
	///   - token: Authentication token.
	///   - org: The InfluxDB organization.
	///   - bucket: The InfluxDB bucket.
	///   - precision: Precision for the unix timestamps within the body line-protocol.
	///   - batchSize: The maximum number of points to batch before writing to InfluxDB. Defaults to 5000.
	///   - throttleInterval: The maximum number of seconds to wait before writing a batch of points. Defaults to 5.
	///   - timeoutIntervalForRequest: Timeout interval to use when waiting for additional data.
	///   - timeoutIntervalForResource: Maximum amount of time that a resource request should be allowed to take.
	///   - enableGzip: Enable Gzip compression for HTTP requests.
	///   - connectionProxyDictionary: Enable Gzip compression for HTTP requests.
	///   - urlSessionDelegate: A delegate to handle HTTP session-level events.
	///   - debugging: optional Enable debugging for HTTP request/response. Default `false`.
	///   - protocolClasses: optional array of extra protocol subclasses that handle requests.
	///   - measurementNamePolicy: Defines how to name the measurement. Defaults to `.byName`.
	///   - parametersLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "event_name"].
	///   - parameters: Global parameters for all events. Defaults to `[:]`.
	public init(
		url: String,
		token: String,
		org: String,
		bucket: String,
		precision: InfluxDBClient.TimestampPrecision = InfluxDBClient.defaultTimestampPrecision,
		batchSize: Int = 5000,
		throttleInterval: UInt16 = 5,
		timeoutIntervalForRequest: TimeInterval = 60,
		timeoutIntervalForResource: TimeInterval = 60 * 5,
		enableGzip: Bool = false,
		connectionProxyDictionary: [AnyHashable: Any]? = nil,
		urlSessionDelegate: URLSessionDelegate? = nil,
		debugging: Bool? = nil,
		protocolClasses: [AnyClass]? = nil,
		measurementNamePolicy: MeasurementNamePolicy = .byName,
		parametersLabelsAsTags: LabelsSet = .analyticsDefault,
		parameters: Analytics.Parameters = [:]
	) {
		self.init(
			options: BucketWriterOptions(
				url: url,
				token: token,
				org: org,
				bucket: bucket,
				precision: precision,
				batchSize: batchSize,
				throttleInterval: throttleInterval,
				timeoutIntervalForRequest: timeoutIntervalForRequest,
				timeoutIntervalForResource: timeoutIntervalForResource,
				enableGzip: enableGzip,
				connectionProxyDictionary: connectionProxyDictionary,
				urlSessionDelegate: urlSessionDelegate,
				debugging: debugging,
				protocolClasses: protocolClasses
			),
			measurementNamePolicy: measurementNamePolicy,
			parametersLabelsAsTags: parametersLabelsAsTags,
			parameters: parameters
		)
	}

	public func send(event: Analytics.Event, file: String, function: String, line: UInt, source: String) {
		let measurement = measurementNamePolicy.measurement(event.name)
		var data: [(String, InfluxDBClient.Point.FieldValue)] = [
			(.InfluxDBAnalyticsLabels.line, .uint(line)),
			(.InfluxDBAnalyticsLabels.function, .string(function)),
			(.InfluxDBAnalyticsLabels.file, .string(file)),
			(.InfluxDBAnalyticsLabels.source, .string(source)),
		]
		if measurement != event.name {
			data.append((.InfluxDBAnalyticsLabels.event_name, .string(event.name)))
		}
		data += parameters
			.merging(event.parameters) { _, new in new }
			.map { ($0.key, $0.value.fieldValue) }

		api.write(
			measurement: measurement,
			tags: [:],
			fields: [:],
			unspecified: data,
			measurementID: uuid,
			telemetryType: "analytics",
			labelsAsTags: labelsAsTags
		)
	}

	public struct MeasurementNamePolicy: _SwiftAnalyticsSendableAnalyticsHandler {

		/// Use the event name as the measurement name.
		public static var byName: MeasurementNamePolicy {
			MeasurementNamePolicy { $0 }
		}

		/// Use a global measurement name.
		public static func global(_ value: String) -> MeasurementNamePolicy {
			MeasurementNamePolicy { _ in value }
		}

		/// Use `events` as the measurement name.
		public static var global: MeasurementNamePolicy {
			.global("events")
		}

		#if compiler(>=5.6)
		public let measurement: @Sendable (_ name: String) -> String

		public init(_ measurement: @escaping @Sendable (_ name: String) -> String) {
			self.measurement = measurement
		}
		#else
		public let measurement: (_ name: String) -> String

		public init(_ measurement: @escaping (_ name: String) -> String) {
			self.measurement = measurement
		}
		#endif
	}
}

public extension String {

	enum InfluxDBAnalyticsLabels {

		static let source = "source"
		static let line = "line"
		static let function = "function"
		static let file = "file"
		static let event_name = "event_name"
	}
}

public extension LabelsSet {

	static let analyticsDefault: LabelsSet = [
		.InfluxDBAnalyticsLabels.source,
		.InfluxDBAnalyticsLabels.event_name,
	]
}

private extension Analytics.ParametersValue {

	var fieldValue: InfluxDBClient.Point.FieldValue {
		switch self {
		case let .string(value): return .string(value)
		case let .int(value): return .int(value)
		case let .double(value): return .double(value)
		case let .bool(value): return .boolean(value)
		default: return .string(description)
		}
	}
}
