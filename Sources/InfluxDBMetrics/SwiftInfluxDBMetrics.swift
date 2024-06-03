@_exported import CoreMetrics
import Foundation
@_exported import InfluxDBSwift
import Logging
@_exported import SwiftInfluxDBCore

/// InfluxDB Metrics Factory.
/// `InfluxDBMetricsFactory` creates a unique handler for each combination of metric types, labels, and tags.
/// In InfluxDB, tags are indexed dimensions. By default, all dimensions are indexed as tags.
/// Use the `dimensionsLabelsAsTags` parameter to customize which dimensions are treated as tags.
///
/// Example of bootstrapping the Metrics System:
/// ```swift
/// MetricsSystem.bootstrap(
///     InfluxDBMetricsFactory(
///         url: "http://localhost:8086",
///         token: "your-token",
///         org: "your-org-name",
///         bucket: "your-bucket-name",
///         client: client,
///         precision: .ms, // Optional
///         batchSize: 5000, // Optional
///         throttleInterval: 10, // Optional
///         dimensionsLabelsAsTags: .all // Optional
///     )
/// )
/// ```
public struct InfluxDBMetricsFactory: @unchecked Sendable {

	private let api: InfluxDBWriter
	private let box = NIOLockedValueBox([AnyHashable: AnyInfluxMetricHandler]())
	private let dimensions: [(String, String)]
    private let coldStart: Bool
    private let identifyingPolicy: MetricIdentifyingPolicy

	/// Create a new `InfluxDBMetricsFactory`.
	/// - Parameters:
	///   - options: The InfluxDB writer options.
	///   - intervalType: The interval type for the metrics. Can be `regular` or `irregular`.
	///   Difference between them you can found in [InfluxDB documentation](https://www.influxdata.com/blog/what-is-the-difference-between-metrics-and-events/).
	///   Regular interval type creates a timer with a fixed interval and sends all collected metrics every interval. Irregular interval type sends metrics only when they are triggered. Defaults to irregular.
	///   - dimensionsLabelsAsTags: The set of labels to use as tags. Defaults to all.
	///   - dimensions: Global dimensions for all metrics. Defaults to `[]`.
    ///   - identifyingPolicy: A policy that determines how metrics counters are identified.
    ///   This can be based on label alone or by a combination of label and dimension.
    ///   Using labels provides a broad identification, while including dimensions allows
    ///   for more granular and contextual tracking of metrics.
    ///   - coldStart: A Boolean value indicating whether the metrics should reset on the first start. `true` if the metrics reset on the initial launch; `false` if the metrics persist across launches.
	public init(
		options: BucketWriterOptions,
		intervalType: IntervalType = .irregular,
		dimensionsLabelsAsTags: LabelsSet = .all,
		dimensions: [(String, String)] = [],
        identifyingPolicy: MetricIdentifyingPolicy = .byLabelAndDimensions,
        coldStart: Bool = false
	) {
		api = InfluxDBWriter(
			options: options,
			intervalType: intervalType,
			labelsAsTags: dimensionsLabelsAsTags,
			telemetryType: "metrics"
		)
        self.coldStart = coldStart
		self.dimensions = dimensions
        self.identifyingPolicy = identifyingPolicy
	}

	/// Create a new `InfluxDBMetricsFactory`.
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
	///   - intervalType: The interval type for the metrics. Can be `regular` or `irregular`.
	///   Difference between them you can found in [InfluxDB documentation](https://www.influxdata.com/blog/what-is-the-difference-between-metrics-and-events/).
	///   Regular interval type creates a timer with a fixed interval and sends all collected metrics every interval. Irregular interval type sends metrics only when they are triggered. Defaults to irregular.
	///   - dimensionsLabelsAsTags: The set of labels to use as tags. Defaults to all.
	///   - dimensions: Global dimensions for all metrics. Defaults to `[]`.
    ///   - identifyingPolicy: A policy that determines how metrics counters are identified.
    ///   This can be based on label alone or by a combination of label and dimension.
    ///   Using labels provides a broad identification, while including dimensions allows
    ///   for more granular and contextual tracking of metrics.
    ///   - coldStart: A Boolean value indicating whether the metrics should reset on the first start. `true` if the metrics reset on the initial launch; `false` if the metrics persist across launches.
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
		intervalType: IntervalType = .irregular,
		dimensionsLabelsAsTags: LabelsSet = .all,
		dimensions: [(String, String)] = [],
        identifyingPolicy: MetricIdentifyingPolicy = .byLabelAndDimensions,
        coldStart: Bool = false
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
			intervalType: intervalType,
			dimensionsLabelsAsTags: dimensionsLabelsAsTags,
			dimensions: dimensions,
            identifyingPolicy: identifyingPolicy,
            coldStart: coldStart
		)
	}
}

extension InfluxDBMetricsFactory: MetricsFactory {

	public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        makeHandler(Counter.self, type: "counter", label: label, dimensions: dimensions)
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
        return makeHandler(AggregateRecorder.self, type: type, label: label, dimensions: dimensions)
	}

	public func makeMeter(label: String, dimensions: [(String, String)]) -> MeterHandler {
		makeFloatingPointCounter(type: "meter", label: label, dimensions: dimensions)
	}

	public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        makeHandler(TimerMetric.self, type: "timer", label: label, dimensions: dimensions)
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
		guard let metric = handler as? any InfluxMetric else {
			return
		}
		return box.withLockedValue { store in
			store.removeValue(forKey: metric.id)
		}
	}

	func makeFloatingPointCounter(type: String, label: String, dimensions: [(String, String)]) -> FloatingCounter {
        makeHandler(FloatingCounter.self, type: type, label: label, dimensions: dimensions)
	}

	@inline(__always)
    func makeHandler<H: InfluxMetric>(_: H.Type, type: String, label: String, dimensions: [(String, String)]) -> H {
        box.withLockedValue { store -> H in
            let dimensions = self.dimensions + dimensions
            let handlerID = HandlerID(
                label: label,
                type: type,
                dimensions: identifyingPolicy == .byLabel ? [] : dimensions,
                labelsAsTags: api.labelsAsTags
            )
            if let value = store[handlerID] as? H.Handler {
                return H.init(handler: value, dimensions: dimensions, coldStart: coldStart)
            }
            if store[handlerID] != nil {
                Logger(label: "SwiftInfluxDBMetrics")
                    .error("A metric named '\(label)' already exists.")
            }
            
            let handler = H.Handler.init(id: handlerID, api: api)
            store[handlerID] = handler

            return H.init(
                handler: handler,
                dimensions: dimensions,
                coldStart: coldStart
            )
        }
	}
}
