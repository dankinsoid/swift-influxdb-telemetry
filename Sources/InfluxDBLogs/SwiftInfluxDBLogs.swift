import Foundation
@_exported import InfluxDBSwift
@_exported import Logging
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
	public var label: String
	public var metadataProvider: Logger.MetadataProvider?
	private let api: InfluxDBWriter
	private let uuid = UUID()
	private let measurementNamePolicy: MeasurementNamePolicy
	private let labelsAsTags: LabelsSet

	/// Create a new `InfluxDBLogHandler`.
	/// - Parameters:
	///   - label: The logger label.
	///   - options: The InfluxDB writer options.
	///   - measurementNamePolicy: Defines how to name the measurement. Defaults to `.byLabel`.
	///   - metadataLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "log_level", "logger_label"].
	///   - logLevel: The log level to use. Defaults to `.info`.
	///   - metadata: The metadata to use. Defaults to `[:]`.
	///   - metadataProvider: A metadata provider to use.
	public init(
		label: String,
		options: BucketWriterOptions,
		measurementNamePolicy: MeasurementNamePolicy = .byLabel,
		metadataLabelsAsTags: LabelsSet = .loggingDefault,
		logLevel: Logger.Level = .info,
		metadata: Logger.Metadata = [:],
		metadataProvider: Logger.MetadataProvider? = nil
	) {
		self.metadata = metadata
		self.logLevel = logLevel
		self.label = label
		self.measurementNamePolicy = measurementNamePolicy
		self.metadataProvider = metadataProvider
		self.labelsAsTags = metadataLabelsAsTags
		api = InfluxDBWriter(options: options)
	}

	/// Create a new `InfluxDBLogHandler`.
	/// - Parameters:
	///   - label: The logger label.
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
	///   - measurementNamePolicy: Defines how to name the measurement. Defaults to `.byLabel`.
	///   - metadataLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "log_level", "logger_label"].
	///   - logLevel: The log level to use. Defaults to `.info`.
	///   - metadata: The metadata to use. Defaults to `[:]`.
	///   - metadataProvider: A metadata provider to use.
	public init(
		label: String,
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
		measurementNamePolicy: MeasurementNamePolicy = .byLabel,
		metadataLabelsAsTags: LabelsSet = .loggingDefault,
		logLevel: Logger.Level = .info,
		metadata: Logger.Metadata = [:],
		metadataProvider: Logger.MetadataProvider? = nil
	) {
		self.init(
			label: label,
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
			metadataLabelsAsTags: metadataLabelsAsTags,
			logLevel: logLevel,
			metadata: metadata,
			metadataProvider: metadataProvider
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
		guard label != InfluxDBWriter.loggerLabel else { return }
		let measurement = measurementNamePolicy.measurement(level, source, label)
		var data: [(String, InfluxDBClient.Point.FieldValue)] = [
			(.InfluxDBLogLabels.line, .uint(line)),
			(.InfluxDBLogLabels.function, .string(function)),
			(.InfluxDBLogLabels.file, .string(file)),
			(.InfluxDBLogLabels.source, .string(source)),
			(.InfluxDBLogLabels.log_level, .string(level.rawValue.uppercased())),
		]
		if measurement != label {
			data.append((.InfluxDBLogLabels.logger_label, .string(label)))
		}

		data += self.metadata
			.merging(metadataProvider?.get() ?? [:]) { o, _ in o }
			.merging(metadata ?? [:]) { _, new in new }
			.map { ($0.key, $0.value.fieldValue) }

		api.write(
			measurement: measurement,
			tags: [:],
			fields: ["message": .string(message.description)],
			unspecified: data,
			measurementID: uuid,
			telemetryType: "logging",
			labelsAsTags: labelsAsTags
		)
	}

	public struct MeasurementNamePolicy: _SwiftLogSendableLogHandler {

		/// Use the log level as the measurement name.
		public static var byLevel: MeasurementNamePolicy {
			MeasurementNamePolicy { level, _, _ in level.rawValue }
		}

		/// Use the log source as the measurement name.
		public static var bySource: MeasurementNamePolicy {
			MeasurementNamePolicy { _, source, _ in source }
		}

		/// Use the logger label as the measurement name.
		public static var byLabel: MeasurementNamePolicy {
			MeasurementNamePolicy { _, _, label in label }
		}

		/// Use a global measurement name.
		public static func global(_ value: String) -> MeasurementNamePolicy {
			MeasurementNamePolicy { _, _, _ in value }
		}

		/// Use `logs` as the measurement name.
		public static var global: MeasurementNamePolicy {
			.global("logs")
		}

		#if compiler(>=5.6)
		public let measurement: @Sendable (
			_ level: Logger.Level,
			_ source: String,
			_ label: String
		) -> String

		public init(_ measurement: @escaping @Sendable (_ level: Logger.Level, _ source: String, _ label: String) -> String) {
			self.measurement = measurement
		}
		#else
		public let measurement: (
			_ level: Logger.Level,
			_ source: String,
			_ label: String
		) -> String

		public init(_ measurement: @escaping (_ level: Logger.Level, _ source: String, _ label: String) -> String) {
			self.measurement = measurement
		}
		#endif
	}
}

public extension String {

	enum InfluxDBLogLabels {

		static let log_level = "log_level"
		static let source = "source"
		static let line = "line"
		static let function = "function"
		static let file = "file"
		static let logger_label = "logger_label"
	}
}

public extension LabelsSet {

	static let loggingDefault: LabelsSet = [
		.InfluxDBLogLabels.source,
		.InfluxDBLogLabels.log_level,
		.InfluxDBLogLabels.logger_label,
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
