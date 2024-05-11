import Foundation
@_exported import InfluxDBSwift
@_exported import Instrumentation
@_exported import SwiftInfluxDBCore
@_exported import Tracing

/// InfluxDB Tracer.
/// `InfluxDBTracer` writes spans to InfluxDB with "traces" measurement name.
/// In InfluxDB, tags are indexed dimensions. By default, all dimensions are indexed as tags.
/// Use the `attributesLabelsAsTags` parameter to customize which attrubutes are treated as tags.
///
/// Example of bootstrapping the Instrumentation System:
/// ```swift
/// InstrumentationSystem.bootstrap(
///     InfluxDBTracer(
///         url: "http://localhost:8086",
///         token: "your-token",
///         org: "your-org-name",
///         bucket: "your-bucket-name",
///         client: client,
///         precision: .ms, // Optional
///         batchSize: 5000, // Optional
///         throttleInterval: 10, // Optional
///         attributesLabelsAsTags: .none // Optional
///     )
/// )
/// ```
public struct InfluxDBTracer: Tracer {

	let api: InfluxDBWriter
	let measurement: String

	/// Create a new `InfluxDBTracer`.
	/// - Parameters:
	///   - options: The InfluxDB writer options.
	///   - attributesLabelsAsTags: The set of labels to use as tags. Defaults to empty.
	public init(
		options: BucketWriterOptions,
		measurement: String = "traces",
		attributesLabelsAsTags: LabelsSet = .empty
	) {
		api = InfluxDBWriter(
			options: options,
			labelsAsTags: attributesLabelsAsTags,
            telemetryType: "tracing"
		)
		self.measurement = measurement
	}

	/// Create a new `InfluxDBTracer`.
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
	///   - attributesLabelsAsTags: The set of labels to use as tags. Defaults to empty.
	public init(
		url: String,
		token: String,
		org: String,
		bucket: String,
		measurement: String = "traces",
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
		attributesLabelsAsTags: LabelsSet = .empty
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
			measurement: measurement,
			attributesLabelsAsTags: attributesLabelsAsTags
		)
	}

	public func extract<Carrier, Extract: Extractor>(
		_ carrier: Carrier,
		into context: inout ServiceContext,
		using extractor: Extract
	) where Extract.Carrier == Carrier {
		let traceID = extractor.extract(key: "trace-id", from: carrier) ?? UUID().uuidString
		let spanID = extractor.extract(key: "span-id", from: carrier) ?? UUID().uuidString
		if context.spanContext == nil {
			context.spanContext = InfluxDBSpanContext(traceID: traceID, spanID: spanID)
		} else {
			context.spanContext?.traceID = traceID
		}
	}

	public func inject<Carrier, Inject: Injector>(
		_ context: ServiceContext,
		into carrier: inout Carrier,
		using injector: Inject
	) where Inject.Carrier == Carrier {
		if let traceID = context.spanContext?.traceID {
			injector.inject(traceID, forKey: "trace-id", into: &carrier)
		}
		if let spanID = context.spanContext?.spanID {
			injector.inject(spanID, forKey: "span-id", into: &carrier)
		}
	}

	public func startSpan<Instant: TracerInstant>(
		_ operationName: String,
		context: @autoclosure () -> ServiceContext,
		ofKind kind: SpanKind,
		at instant: @autoclosure () -> Instant,
		function: String,
		file fileID: String,
		line: UInt
	) -> Span {
		let startNano = instant().nanosecondsSinceEpoch
		let parentContext = context()
		var childContext = parentContext

		let traceID: String
		let spanID = UUID().uuidString

		if let parentSpanContext = parentContext.spanContext {
			traceID = parentSpanContext.traceID
		} else {
			traceID = UUID().uuidString
		}

		let spanContext = InfluxDBSpanContext(
			traceID: traceID,
			spanID: spanID,
			parentSpanID: parentContext.spanContext?.spanID
		)
		childContext.spanContext = spanContext

		return Span(
			operationName: operationName,
			kind: kind,
			context: context(),
			attributes: [:],
			startTimeNanosecondsSinceEpoch: startNano
		) { [api] span, endTimeNanosecondsSinceEpoch in
			var parameters: [(String, InfluxDBClient.Point.FieldValue)] = []
			span.attributes.forEach { name, attribute in
				parameters.append((name, attribute.fieldValue))
			}
			let error = span.events.last(where: { $0.name == "exception" })?
				.attributes
				.get("exception.message")?
				.fieldValue
			api.write(
				measurement: measurement,
				tags: [
					"trace_id": traceID,
					"span_id": spanID,
					"parent_span_id": parentContext.spanContext?.spanID,
					"operation_name": span.operationName,
					"status": span.status?.code != .ok || error != nil ? "ERROR" : "OK",
				]
				.compactMapValues { $0 },
				fields: [
					"start_time": .uint(UInt(startNano)),
					"duration": .uint(UInt(endTimeNanosecondsSinceEpoch - startNano)),
					"message": (span.status?.message).map(InfluxDBClient.Point.FieldValue.string) ?? error,
					"links": .string(span.links.compactMap { $0.context.spanContext?.spanID }.description),
					"events": .string(span.events.map(\.description).description),
				]
				.compactMapValues { $0 },
				unspecified: parameters,
				measurementID: UUID()
			)
		}
	}

	public func forceFlush() {
		api.flush()
	}

	public final class Span: @unchecked Sendable, Tracing.Span {

		public let kind: SpanKind
		public let context: ServiceContext

		public var operationName: String {
			get { _operationName.withLockedValue { $0 } }
			set { _operationName.withLockedValue { $0 = newValue } }
		}

		private let _operationName: NIOLockedValueBox<String>

		public var attributes: SpanAttributes {
			get { _attributes.withLockedValue { $0 } }
			set { _attributes.withLockedValue { $0 = newValue } }
		}

		private let _attributes: NIOLockedValueBox<SpanAttributes>

		public var status: SpanStatus? { _status.withLockedValue { $0 } }
		private let _status = NIOLockedValueBox<SpanStatus?>(nil)

		public var events: [SpanEvent] { _events.withLockedValue { $0 } }
		private let _events = NIOLockedValueBox([SpanEvent]())

		public var links: [SpanLink] { _links.withLockedValue { $0 } }
		private let _links = NIOLockedValueBox([SpanLink]())

		public let startTimeNanosecondsSinceEpoch: UInt64

		public var endTimeNanosecondsSinceEpoch: UInt64? { _endTimeNanosecondsSinceEpoch.withLockedValue { $0 } }
		private let _endTimeNanosecondsSinceEpoch = NIOLockedValueBox<UInt64?>(nil)
		private let onEnd: @Sendable (Span, _ endTimeNanosecondsSinceEpoch: UInt64) -> Void

		public var isRecording: Bool { endTimeNanosecondsSinceEpoch == nil }

		public init(
			operationName: String,
			kind: SpanKind,
			context: ServiceContext,
			attributes: SpanAttributes,
			startTimeNanosecondsSinceEpoch: UInt64,
			onEnd: @escaping @Sendable (Span, _ endTimeNanosecondsSinceEpoch: UInt64) -> Void
		) {
			_operationName = NIOLockedValueBox(operationName)
			self.kind = kind
			self.context = context
			_attributes = NIOLockedValueBox(attributes)
			self.startTimeNanosecondsSinceEpoch = startTimeNanosecondsSinceEpoch
			self.onEnd = onEnd
		}

		public func setStatus(_ status: SpanStatus) {
			guard self.status?.code != .ok else { return }

			let status: SpanStatus = {
				switch status.code {
				case .ok:
					return SpanStatus(code: .ok, message: nil)
				case .error:
					return status
				}
			}()

			_status.withLockedValue { $0 = status }
		}

		public func addEvent(_ event: SpanEvent) {
			_events.withLockedValue { $0.append(event) }
		}

		public func recordError(
			_ error: Error,
			attributes: SpanAttributes,
			at instant: @autoclosure () -> some TracerInstant
		) {
			var eventAttributes: SpanAttributes = [
				"exception.type": .string(String(describing: type(of: error))),
				"exception.message": .string(String(describing: error)),
			]
			eventAttributes.merge(attributes)

			let event = SpanEvent(
				name: "exception",
				at: instant(),
				attributes: eventAttributes
			)
			addEvent(event)
		}

		public func addLink(_ link: SpanLink) {
			_links.withLockedValue { $0.append(link) }
		}

		public func end(at instant: @autoclosure () -> some TracerInstant) {
			let endTimeNanosecondsSinceEpoch = instant().nanosecondsSinceEpoch
			_endTimeNanosecondsSinceEpoch.withLockedValue { $0 = endTimeNanosecondsSinceEpoch }
			onEnd(self, endTimeNanosecondsSinceEpoch)
		}
	}
}

public extension ServiceContext {

	/// The span context.
	internal(set) var spanContext: InfluxDBSpanContext? {
		get {
			self[SpanContextKey.self]
		}
		set {
			self[SpanContextKey.self] = newValue
		}
	}
}

public struct InfluxDBSpanContext {

	public var traceID: String
	public var spanID: String
	public var parentSpanID: String?
}

private enum SpanContextKey: ServiceContextKey {

	typealias Value = InfluxDBSpanContext
	static let nameOverride: String? = "influxdb-span-context"
}

private extension SpanAttribute {

	var fieldValue: InfluxDBClient.Point.FieldValue {
		switch self {
		case let .string(value):
			return .string(value)
		case let .bool(value):
			return .boolean(value)
		case let .int32(value):
			return .int(Int(value))
		case let .int64(value):
			return .int(Int(value))
		case let .double(value):
			return .double(value)
		case let .boolArray(value):
			return .string(value.description)
		case let .int32Array(value):
			return .string(value.description)
		case let .int64Array(value):
			return .string(value.description)
		case let .doubleArray(value):
			return .string(value.description)
		case let .stringArray(value):
			return .string(value.description)
		case .__DO_NOT_SWITCH_EXHAUSTIVELY_OVER_THIS_ENUM_USE_DEFAULT_INSTEAD:
			return .string("NULL")
		case let .stringConvertible(value):
			return .string(value.description)
		case let .stringConvertibleArray(value):
			return .string(value.description)
		}
	}
}

private extension SpanEvent {

	var description: String {
		var result = "\(name) - \(nanosecondsSinceEpoch)"
		if !attributes.isEmpty {
			var attributesString = "["
			attributes.forEach { name, attribute in
				attributesString += "\(name): \(attribute.fieldValue.string), "
			}
			attributesString.removeLast(2)
			attributesString += "]"
			result += " - \(attributes)"
		}
		return result
	}
}
