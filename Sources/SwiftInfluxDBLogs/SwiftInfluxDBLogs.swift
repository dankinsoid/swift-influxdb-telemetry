import Logging
import InfluxDBSwift
@_exported import SwiftInfluxDBCore

/// InfluxDB Log Handler.
/// `InfluxDBLogHandler` constructs a measurement for each log entry, using the logger's name as the measurement name.
/// Log messages are stored in the `message` field, while log metadata may either be stored as fields or tags, based on the `metadataLabelsAsTags` parameter.
/// Default metadata such as `file`, `source`, `log_level`, etc., can be indexed as tags; these defaults are modifiable via the `metadataLabelsAsTags` parameter.
/// Default metadata labels are defined in the `String.InfluxDBLogHandlerLabels` namespace as static constants.
///
/// Usage:
/// ```swift
/// LoggingSystem.bootstrap { name in
///     InfluxDBLogHandler(
///         name: name,
///         bucket: "your-bucket-name",
///         org: "your-org-name",
///         client: client,
///         precision: .ms, // Optional
///         batchSize: 5000, // Optional
///         throttleInterval: 5, // Optional
///         metadataLabelsAsTags: InfluxDBLogHandler.defaultMetadataLabelsAsTags.union([.InfluxDBLogHandlerLabels.file]), // Optional
///         logLevel: .info, // Optional
///         metadata: [:] // Optional
///     )
/// }
/// ```
public struct InfluxDBLogHandler: LogHandler {
    
    /// Default metadata labels as tags.
    public static let defaultMetadataLabelsAsTags: LabelsSet = [
        .InfluxDBLogHandlerLabels.source,
        .InfluxDBLogHandlerLabels.log_level
    ]
    
    public var metadata: Logger.Metadata
    public var logLevel: Logger.Level
    public var name: String
    private let api: InfluxDBWriter
    
    /// Create a new `InfluxDBLogHandler`.
    /// - Parameters:
    ///   - name: The logger name. Logger name used as a measurement name in InfluxDB.
    ///   - client: The InfluxDB client to use.
    ///   - configs: The InfluxDB writer configurations.
    ///   - metadataLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "log_level"].
    ///   - logLevel: The log level to use. Defaults to `.info`.
    ///   - metadata: The metadata to use. Defaults to `[:]`.
    /// - Important: You should call `client.close()` at the end of your application to release allocated resources.
    public init(
        name: String,
        client: InfluxDBClient,
        configs: InfluxDBWriterConfigs,
        metadataLabelsAsTags: LabelsSet = Self.defaultMetadataLabelsAsTags,
        logLevel: Logger.Level = .info,
        metadata: Logger.Metadata = [:]
    ) {
        self.metadata = metadata
        self.logLevel = logLevel
        self.name = name
        api = InfluxDBWriter(
            client: client,
            configs: configs,
            labelsAsTags: metadataLabelsAsTags
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
            (.InfluxDBLogHandlerLabels.line, .uint(line)),
            (.InfluxDBLogHandlerLabels.function, .string(function)),
            (.InfluxDBLogHandlerLabels.file, .string(file)),
            (.InfluxDBLogHandlerLabels.source, .string(source)),
            (.InfluxDBLogHandlerLabels.log_level, .string(level.rawValue.uppercased()))
        ] + self.metadata
            .merging(metadata ?? [:]) { _, new in new }
            .map { ($0.key, $0.value.fieldValue) }

        api.write(
            measurement: name,
            tags: [:],
            fields: ["message": .string(message.description)],
            unspecified: data
        )
    }
}

public extension String {
    
    enum InfluxDBLogHandlerLabels {
        
        static let log_level = "log_level"
        static let source = "source"
        static let line = "line"
        static let function = "function"
        static let file = "file"
    }
}

private extension Logger.MetadataValue {
    
    var fieldValue: InfluxDBClient.Point.FieldValue {
        switch self {
        case .string(let value): return .string(value)
        case .stringConvertible(let value):
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
