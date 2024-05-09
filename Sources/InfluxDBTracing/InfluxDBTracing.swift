import InfluxDBSwift
@_exported import SwiftInfluxDBCore
import Tracing
import Instrumentation
import Foundation

public struct InfluxDBTracer: Tracer {

    public func extract<Carrier, Extract: Extractor>(
        _ carrier: Carrier,
        into context: inout ServiceContext,
        using extractor: Extract
    ) where Extract.Carrier == Carrier {
        let traceID = extractor.extract(key: "trace-id", from: carrier) ?? UUID().uuidString
        context.traceID = traceID
    }

    public func inject<Carrier, Inject: Injector>(
        _ context: ServiceContext,
        into carrier: inout Carrier,
        using injector: Inject
    ) where Inject.Carrier == Carrier {
        guard let traceID = context.traceID else {
            return
        }
        injector.inject(traceID, forKey: "trace-id", into: &carrier)
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
        Span(
            attributes: [:],
            isRecording: true,
            context: context(),
            operationName: operationName
        )
    }

    public func forceFlush() {
        
    }

    public final class Span: @unchecked Sendable, Tracing.Span {

        public var attributes: SpanAttributes
        public var isRecording: Bool
        public var context: ServiceContext
        public var operationName: String

        public init(
            attributes: SpanAttributes,
            isRecording: Bool,
            context: ServiceContext,
            operationName: String
        ) {
            self.attributes = attributes
            self.isRecording = isRecording
            self.context = context
            self.operationName = operationName
        }

        public func setStatus(_ status: SpanStatus) {
        }

        public func addEvent(_ event: SpanEvent) {
            
        }

        public func addLink(_ link: SpanLink) {
            
        }

        public func end<Instant: TracerInstant>(at instant: @autoclosure () -> Instant) {
            
        }

        public func recordError<Instant: TracerInstant>(
            _ error: Error,
            attributes: SpanAttributes,
            at instant: @autoclosure () -> Instant
        ) {
            
        }
    }
}

extension ServiceContext {

    /// The span context.
    public internal(set) var spanContext: InfluxDBSpanContext? {
        get {
            self[SpanContextKey.self]
        }
        set {
            self[SpanContextKey.self] = newValue
        }
    }

    var traceID: String? {
        get {
            self[SpanContextKey.self]?.traceID
        }
        set {
            self[SpanContextKey.self]?.traceID = newValue
        }
    }
}

public struct InfluxDBSpanContext {

    public var traceID: String?
}

private enum SpanContextKey: ServiceContextKey {

    typealias Value = InfluxDBSpanContext
    static let nameOverride: String? = "influxdb-span-context"
}
