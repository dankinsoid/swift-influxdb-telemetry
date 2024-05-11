import Foundation
import InfluxDBSwift
import SwiftAnalytics
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

	/// Create a new `InfluxDBAnalyticsHandler`.
	/// - Parameters:
	///   - options: The InfluxDB writer options.
	///   - parametersLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source"].
	///   - parameters: Global parameters for all events. Defaults to `[:]`.
	public init(
		options: BucketWriterOptions,
		parametersLabelsAsTags: LabelsSet = .analyticsDefault,
		parameters: Analytics.Parameters = [:]
	) {
		api = InfluxDBWriter(
			options: options,
			labelsAsTags: parametersLabelsAsTags,
            telemetryType: "analytics"
		)
		self.parameters = parameters
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
	///   - parametersLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source"].
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
			parametersLabelsAsTags: parametersLabelsAsTags,
			parameters: parameters
		)
	}

	public func send(event: Analytics.Event, file: String, function: String, line: UInt, source: String) {
		let data: [(String, InfluxDBClient.Point.FieldValue)] = [
			(.InfluxDBAnalyticsLabels.line, .uint(line)),
			(.InfluxDBAnalyticsLabels.function, .string(function)),
			(.InfluxDBAnalyticsLabels.file, .string(file)),
			(.InfluxDBAnalyticsLabels.source, .string(source)),
		] + parameters
			.merging(event.parameters) { _, new in new }
			.map { ($0.key, $0.value.fieldValue) }

		api.write(
			measurement: event.name,
			tags: [:],
			fields: [:],
			unspecified: data,
			measurementID: uuid
		)
	}
}

public extension String {

	enum InfluxDBAnalyticsLabels {

		static let source = "source"
		static let line = "line"
		static let function = "function"
		static let file = "file"
	}
}

public extension LabelsSet {

	static let analyticsDefault: LabelsSet = [
		.InfluxDBAnalyticsLabels.source,
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
