import SwiftAnalytics
import InfluxDBSwift
@_exported import SwiftInfluxDBCore

/// InfluxDB Log Handler.
/// `InfluxDBAnalyticsHandler` constructs a measurement for all events, using the event's name as the measurement name.
/// Event parameters may either be stored as fields or tags, based on the `parametersLabelsAsTags` parameter.
/// Default parameters such as `fileID`, `source`, etc., can be indexed as tags; these defaults are modifiable via the `parametersLabelsAsTags` parameter.
/// Default parameters labels are defined in the `String.InfluxDBAnalyticsHandlerLabels` namespace as static constants.
///
/// Usage:
/// ```swift
/// AnalyticsSystem.bootstrap(
///     InfluxDBLogHandler(
///         bucket: "your-bucket-name",
///         org: "your-org-name",
///         client: client,
///         precision: .ms, // Optional
///         batchSize: 5000, // Optional
///         throttleInterval: 5, // Optional
///         parametersLabelsAsTags: InfluxDBLogHandler.defaultMetadataLabelsAsTags.union([.InfluxDBLogHandlerLabels.file]) // Optional
///     )
/// )
/// ```
public struct InfluxDBAnalyticsHandler: AnalyticsHandler {

    /// Default metadata labels as tags.
    public static let defaultMetadataLabelsAsTags: LabelsSet = [
        .InfluxDBAnalyticsHandlerLabels.source
    ]

    public var parameters: Analytics.Parameters

    private let api: SwiftInfluxAPI
    
    /// Create a new `InfluxDBAnalyticsHandler`.
    /// - Parameters:
    ///   - bucket: The InfluxDB bucket to use.
    ///   - client: The InfluxDB client to use.
    ///   - precision: The timestamp precision to use. Defaults to milliseconds.
    ///   - batchSize: The maximum number of points to batch before writing to InfluxDB. Defaults to 5000.
    ///   - throttleInterval: The maximum number of seconds to wait before writing a batch of points. Defaults to 5.
    ///   - parametersLabelsAsTags: The set of metadata labels to use as tags. Defaults to ["source", "log_level"].
    /// - Important: You should call `client.close()` at the end of your application to release allocated resources.
    public init(
        bucket: String,
        org: String,
        client: InfluxDBClient,
        precision: InfluxDBClient.TimestampPrecision = .ms,
        batchSize: Int = 5000,
        throttleInterval: UInt16 = 5,
        parametersLabelsAsTags: LabelsSet = Self.defaultMetadataLabelsAsTags,
        parameters: Analytics.Parameters = [:]
    ) {
        api = SwiftInfluxAPI.make(
            client: client,
            bucket: bucket,
            org: org,
            precision: precision,
            batchSize: batchSize,
            throttleInterval: throttleInterval,
            labelsAsTags: parametersLabelsAsTags
        )
        self.parameters = parameters
    }

    public func send(event: Analytics.Event, file: String, function: String, line: UInt, source: String) {
        let data: [(String, InfluxDBClient.Point.FieldValue)] = [
            (.InfluxDBAnalyticsHandlerLabels.line, .uint(line)),
            (.InfluxDBAnalyticsHandlerLabels.function, .string(function)),
            (.InfluxDBAnalyticsHandlerLabels.file, .string(file)),
            (.InfluxDBAnalyticsHandlerLabels.source, .string(source))
        ] + self.parameters
            .merging(event.parameters) { _, new in new }
            .map { ($0.key, $0.value.fieldValue) }

        api.write(
            measurement: event.name,
            tags: [:],
            fields: [:],
            unspecified: data
        )
    }
}

public extension String {

    enum InfluxDBAnalyticsHandlerLabels {

        static let source = "source"
        static let line = "line"
        static let function = "function"
        static let file = "file"
    }
}

private extension Analytics.ParametersValue {

    var fieldValue: InfluxDBClient.Point.FieldValue {
        switch self {
        case .string(let value): return .string(value)
        case .int(let value): return .int(value)
        case .double(let value): return .double(value)
        case .bool(let value): return .boolean(value)
        default: return .string(description)
        }
    }
}
