import Foundation
import InfluxDBSwift
import Logging
@_exported import SwiftInfluxDBCore

/// InfluxDB Log Handler.
/// `InfluxDBLogHandler` constructs a measurement for each log entry, using the logger's name as the measurement name.
/// Log messages are stored in the `message` field, while log metadata may either be stored as fields or tags, based on the `metadataLabelsAsTags` parameter.
/// Default metadata labels are defined in the `String.InfluxDBLogLabels` namespace as static constants.
///
/// Usage:
/// ```swift
/// LoggingSystem.bootstrap { name in
///     InfluxDBLogHandler(
///         name: name,
///         url: "http://localhost:8086",
///         token: "your-token",
///         org: "your-org-name",
///         bucket: "your-bucket-name",
///         precision: .ms, // Optional
///         batchSize: 5000, // Optional
///         throttleInterval: 5, // Optional
///         metadataLabelsAsTags: LabelsSet.loggingDefault.union([.InfluxDBLogLabels.file]), // Optional
///         logLevel: .info, // Optional
///         metadata: [:] // Optional
///     )
/// }
/// ```
public struct InfluxDBLogHandler: LogHandler {

	public var metadata: Logger.Metadata
	public var logLevel: Logger.Level
	public var name: String
	private let api: InfluxDBWriter
	private let uuid = UUID()

	/// Create a new `InfluxDBLogHandler`.
	/// - Parameters:
	///   - name: The logger name. Logger name used as a measurement name in InfluxDB.
	///   - options: The InfluxDB writer options.
	///   - metadataLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "log_level"].
	///   - logLevel: The log level to use. Defaults to `.info`.
	///   - metadata: The metadata to use. Defaults to `[:]`.
	public init(
		name: String,
		options: BucketWriterOptions,
		metadataLabelsAsTags: LabelsSet = .loggingDefault,
		logLevel: Logger.Level = .info,
		metadata: Logger.Metadata = [:]
	) {
		self.metadata = metadata
		self.logLevel = logLevel
		self.name = name
		api = InfluxDBWriter(
			options: options,
			labelsAsTags: metadataLabelsAsTags
		)
	}

	/// Create a new `InfluxDBLogHandler`.
	/// - Parameters:
	///   - name: The logger name. Logger name used as a measurement name in InfluxDB.
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
	///   - metadataLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "log_level"].
	///   - logLevel: The log level to use. Defaults to `.info`.
	///   - metadata: The metadata to use. Defaults to `[:]`.
	public init(
		name: String,
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
		metadataLabelsAsTags: LabelsSet = .loggingDefault,
		logLevel: Logger.Level = .info,
		metadata: Logger.Metadata = [:]
	) {
		self.init(
			name: name,
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
			metadataLabelsAsTags: metadataLabelsAsTags,
			logLevel: logLevel,
			metadata: metadata
		)
	}

	public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
		get { metadata[key] }
		set { metadata[key] = newValue }
	}

	public func log(
		level: Logger.Level,
		message: Logger.Message,
		metadata: Logger.Metadata?,
		source: String,
		file: String,
		function: String,
		line: UInt
	) {
		let data: [(String, InfluxDBClient.Point.FieldValue)] = [
			(.InfluxDBLogLabels.line, .uint(line)),
			(.InfluxDBLogLabels.function, .string(function)),
			(.InfluxDBLogLabels.file, .string(file)),
			(.InfluxDBLogLabels.source, .string(source)),
			(.InfluxDBLogLabels.log_level, .string(level.rawValue.uppercased())),
		] + self.metadata
			.merging(metadata ?? [:]) { _, new in new }
			.map { ($0.key, $0.value.fieldValue) }

		api.write(
			measurement: name,
			tags: [:],
			fields: ["message": .string(message.description)],
			unspecified: data,
			measurementID: uuid
		)
	}
}

public extension String {

	enum InfluxDBLogLabels {

		static let log_level = "log_level"
		static let source = "source"
		static let line = "line"
		static let function = "function"
		static let file = "file"
	}
}

public extension LabelsSet {

	static let loggingDefault: LabelsSet = [
		.InfluxDBLogLabels.source,
		.InfluxDBLogLabels.log_level,
	]
}

private extension Logger.MetadataValue {

	var fieldValue: InfluxDBClient.Point.FieldValue {
		switch self {
		case let .string(value): return .string(value)
		case let .stringConvertible(value):
			if let floating = value as? any BinaryFloatingPoint {
				return .double(Double(floating))
			} else if let integer = value as? any UnsignedInteger {
				return .uint(UInt(integer))
			} else if let integer = value as? any FixedWidthInteger {
				return .int(Int(integer))
			} else if let boolean = value as? Bool {
				return .boolean(boolean)
			}
			return .string(value.description)
		default: return .string(description)
		}
	}
}
