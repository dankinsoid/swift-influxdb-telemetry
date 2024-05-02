import CoreMetrics
import InfluxDBSwift
@_exported import SwiftInfluxDBCore
import Logging

/// InfluxDB Metrics Factory.
/// `InfluxDBMetricsFactory` creates a unique handler for each combination of metric types, labels, and tags.
/// In InfluxDB, tags are indexed dimensions. By default, all dimensions are indexed as tags.
/// Use the `dimensionsLabelsAsTags` parameter to customize which dimensions are treated as tags.
///
/// Example of bootstrapping the Metrics System:
/// ```swift
/// MetricsSystem.bootstrap(
///     InfluxDBMetricsFactory(
///         bucket: "your-bucket-name",
///         org: "your-org-name",
///         client: client,
///         precision: .ms, // Optional
///         batchSize: 5000, // Optional
///         throttleInterval: 10, // Optional
///         dimensionsLabelsAsTags: .all // Optional
///     )
/// )
/// ```

public struct InfluxDBMetricsFactory: Sendable {
    
    private let api: SwiftInfluxAPI
    private let box = NIOLockedValueBox([HandlerID: InfluxMetric]())
    
    /// Create a new `InfluxDBMetricsFactory`.
    /// - Parameters:
    ///   - bucket: The InfluxDB bucket to use.
    ///   - client: The InfluxDB client to use.
    ///   - precision: The timestamp precision to use. Defaults to milliseconds.
    ///   - batchSize: The maximum number of points to batch before writing to InfluxDB. Defaults to 5000. This default is based on [official recommendations](https://docs.influxdata.com/influxdb/v2/write-data/best-practices/optimize-writes/).
    ///   - throttleInterval: The maximum number of seconds to wait before writing a batch of points. Defaults to 10.
    ///   - dimensionsLabelsAsTags: The set of labels to use as tags. Defaults to all.
    /// - Important: You should call `client.close()` at the end of your application to release allocated resources.
    public init(
        bucket: String,
        org: String,
        client: InfluxDBClient,
        precision: InfluxDBClient.TimestampPrecision = .ms,
        batchSize: Int = 5000,
        throttleInterval: UInt16 = 10,
        dimensionsLabelsAsTags: LabelsSet = .all
    ) {
        api = SwiftInfluxAPI.make(
            client: client,
            bucket: bucket,
            org: org,
            precision: precision,
            batchSize: batchSize,
            throttleInterval: throttleInterval,
            labelsAsTags: dimensionsLabelsAsTags
        )
    }
}

extension InfluxDBMetricsFactory: MetricsFactory {
    
    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        makeHandler(type: "counter", label: label, dimensions: dimensions) { id, fields in
            Counter(api: api, id: id, fields: fields)
        }
    }
    
    public func makeFloatingPointCounter(label: String, dimensions: [(String, String)]) -> FloatingPointCounterHandler {
        makeFloatingPointCounter(type: "floating_counter", label: label, dimensions: dimensions)
    }
    
    public func makeRecorder(
        label: String,
        dimensions: [(String, String)],
        aggregate: Bool
    ) -> RecorderHandler {
        let type = "gauge"
        guard aggregate else {
            return makeFloatingPointCounter(type: type, label: label, dimensions: dimensions)
        }
        return makeHandler(type: type, label: label, dimensions: dimensions) { id, fields in
            AggregateRecorder(api: api, id: id, fields: fields)
        }
    }
    
    public func makeMeter(label: String, dimensions: [(String, String)]) -> MeterHandler {
        makeFloatingPointCounter(type: "meter", label: label, dimensions: dimensions)
    }
    
    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        makeHandler(type: "timer", label: label, dimensions: dimensions) { id, fields in
            TimerMetric(api: api, id: id, fields: fields)
        }
    }
    
    public func destroyCounter(_ handler: CounterHandler) { destroy(handler) }
    public func destroyFloatingPointCounter(_ handler: FloatingPointCounterHandler) { destroy(handler) }
    public func destroyRecorder(_ handler: RecorderHandler) { destroy(handler) }
    public func destroyMeter(_ handler: MeterHandler) { destroy(handler) }
    public func destroyTimer(_ handler: TimerHandler) { destroy(handler) }
}

private extension InfluxDBMetricsFactory {
    
    @inline(__always)
    func destroy(_ handler: Any) {
        guard let metric = handler as? InfluxMetric else {
            return
        }
        return box.withLockedValue { store in
            store.removeValue(forKey: metric.id)
        }
    }
    
    func makeFloatingPointCounter(type: String, label: String, dimensions: [(String, String)]) -> FloatingCounter {
        makeHandler(type: type, label: label, dimensions: dimensions) { id, fields in
            FloatingCounter(api: api, id: id, fields: fields)
        }
    }
    
    @inline(__always)
    func makeHandler<H: InfluxMetric>(type: String, label: String, dimensions: [(String, String)], create: (HandlerID, [(String, String)]) -> H) -> H {
        box.withLockedValue { store -> H in
            var dimensions = dimensions
            let id = HandlerID(label: label, type: type, dimensions: &dimensions, labelsAsTags: api.labelsAsTags)
            guard let value = store[id] as? H else {
                if store[id] != nil {
                    Logger(label: "SwiftInfluxDBMetrics")
                        .error("A metric named '\(label)' already exists.")
                }
                let handler = create(id, dimensions)
                store[id] = handler
                return handler
            }
            return value
        }
    }
}
