import Logging
import InfluxDBSwift
@_exported import SwiftInfluxDBCore

public struct InfluxDBLogHandler: LogHandler {

    public static let defaultMetadataLabelsAsTags: LabelsSet = [
        .InfluxDBLogHandlerLabels.source,
        .InfluxDBLogHandlerLabels.log_level
    ]

    public var metadata: Logger.Metadata
    public var logLevel: Logger.Level
    public var name: String
    private let api: SwiftInfluxAPI

    /// Create a new `InfluxDBLogHandler`.
    /// - Parameters:
    ///   - name: The logger name. Logger name used as a measurement name in InfluxDB.
    ///   - bucket: The InfluxDB bucket to use.
    ///   - client: The InfluxDB client to use.
    ///   - precision: The timestamp precision to use. Defaults to milliseconds.
    ///   - batchSize: The maximum number of points to batch before writing to InfluxDB. Defaults to 5000.
    ///   - throttleInterval: The maximum number of seconds to wait before writing a batch of points. Defaults to 5.
    ///   - metadataLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "log_level"].
    ///   - logLevel: The log level to use. Defaults to `.info`.
    ///   - metadata: The metadata to use. Defaults to `[:]`.
    /// - Important: You should call `client.close()` at the end of your application to release allocated resources.
    public init(
        name: String,
        bucket: String,
        org: String,
        client: InfluxDBClient,
        precision: InfluxDBClient.TimestampPrecision = .ms,
        batchSize: Int = 5000,
        throttleInterval: UInt16 = 5,
        metadataLabelsAsTags: LabelsSet = Self.defaultMetadataLabelsAsTags,
        logLevel: Logger.Level = .info,
        metadata: Logger.Metadata = [:]
    ) {
        self.metadata = metadata
        self.logLevel = logLevel
        self.name = name
        api = SwiftInfluxAPI.make(
            client: client,
            bucket: bucket,
            org: org,
            precision: precision,
            batchSize: batchSize,
            throttleInterval: throttleInterval,
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
            measurement: "\(name)_logger",
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
