import Foundation
@_exported import InfluxDBSwift

public struct InfluxDBWriterConfigs: Equatable, @unchecked Sendable {

    public var bucket: String
    public var org: String
    public var precision: InfluxDBClient.TimestampPrecision
    public var batchSize: Int
    public var throttleInterval: UInt16

    /// Create a new `InfluxDBWriterConfigs`.
    /// - Parameters:
    ///   - bucket: The InfluxDB bucket to use.
    ///   - client: The InfluxDB client to use.
    ///   - precision: The timestamp precision to use. Defaults to milliseconds.
    ///   - batchSize: The maximum number of points to batch before writing to InfluxDB. Defaults to 5000.
    ///   - throttleInterval: The maximum number of seconds to wait before writing a batch of points. Defaults to 5.
    public init(
        bucket: String,
        org: String,
        precision: InfluxDBClient.TimestampPrecision = .ms,
        batchSize: Int = 5000,
        throttleInterval: UInt16 = 5
    ) {
        self.bucket = bucket
        self.org = org
        self.precision = precision
        self.batchSize = batchSize
        self.throttleInterval = throttleInterval
    }
}

package struct InfluxDBWriter: Sendable {

    package let labelsAsTags: LabelsSet
    package let intervalType: IntervalType
    private let api: SwiftInfluxAPI

    package init(
        client: InfluxDBClient,
        configs: InfluxDBWriterConfigs,
        intervalType: IntervalType = .irregular,
        labelsAsTags: LabelsSet
    ) {
        self.labelsAsTags = labelsAsTags
        self.intervalType = intervalType
        self.api = .make(
            client: client,
            configs: configs
        )
    }

    package func load(
        measurement: String,
        tags: [String: String],
        fields: Set<String>
    ) async throws -> QueryAPI.FluxRecord? {
        try await api.load(measurement: measurement, tags: tags, fields: fields)
    }

    package func write(
        measurement: String,
        tags: [String: String],
        fields: [String: InfluxDBClient.Point.FieldValue],
        unspecified: [(String, InfluxDBClient.Point.FieldValue)],
        measurementID: UUID,
        date: Date = Date()
    ) {
        let point = InfluxDBClient.Point(measurement)
        for (key, value) in unspecified {
            if labelsAsTags.contains(key) {
                point.addTag(key: key, value: value.string)
            } else {
                point.addField(key: key, value: value)
            }
        }
        for (key, value) in tags {
            point.addTag(key: key, value: value)
        }
        for (key, value) in fields {
            point.addField(key: key, value: value)
        }
        let nextPoint: @Sendable (Date) -> InfluxDBClient.Point = { date in
            point.time(time: .date(date))
        }
        switch intervalType {
        case .irregular:
            Task {
                await api.add(point: nextPoint(date))
            }
        case let .regular(seconds):
            Task {
                await api.addToTimer(interval: seconds, id: measurementID, startTime: date, point: nextPoint)
            }
        }
    }

    package func close(measurementID: UUID) {
        Task {
            if case let .regular(seconds) = intervalType {
                await api.removeFromTimer(interval: seconds, id: measurementID)
            }
        }
    }
}

private final actor SwiftInfluxAPI: Sendable {

    private static var cache: [String: SwiftInfluxAPI] = [:]

    nonisolated let client: InfluxDBClient
    nonisolated let configs: InfluxDBWriterConfigs
    private let responsesQueue: DispatchQueue
    private var points: [InfluxDBClient.Point]
    private var writeTask: Task<Void, Error>?
    private var timers: [TimeInterval: (Task<Void, Error>, [UUID: (Date) -> InfluxDBClient.Point])] = [:]

    static func make(
        client: InfluxDBClient,
        configs: InfluxDBWriterConfigs
    ) -> SwiftInfluxAPI {
        let key = client.url
        if let api = cache[key] {
            return api
        }
        let api = SwiftInfluxAPI(
            client: client,
            configs: configs
        )
        cache[key] = api
        return api
    }

    private init(
        client: InfluxDBClient,
        configs: InfluxDBWriterConfigs
    ) {
        self.client = client
        self.configs = configs
        var points: [InfluxDBClient.Point] = []
        points.reserveCapacity(configs.batchSize)
        self.points = points
        responsesQueue =  DispatchQueue(label: "InfluxDB.responsesQueue.\(configs.bucket)", qos: .background)
    }

    func load(
        measurement: String,
        tags: [String: String],
        fields: Set<String>
    ) async throws -> QueryAPI.FluxRecord? {
        let filter = ([("_measurement", measurement)] + tags.sorted(by: { $0.key < $1.key }) + fields.map { ("_field", $0) })
            .map { "  |> filter(fn: (r) => r.\($0.key) == \"\($0.value)\")" }
            .joined(separator: "\n")
        
        return try await client.queryAPI.query(
            query: """
from(bucket: "\(configs.bucket)")
  |> range(start: -30d)
\(filter)
  |> last()
""",
            org: configs.org,
            responseQueue: responsesQueue
        )
        .next()
    }

    func add(point: InfluxDBClient.Point) async {
        points.append(point)
        await writeIfNeeded()
    }
    
    func addToTimer(
        interval: TimeInterval,
        id: UUID,
        startTime: Date,
        point: @escaping @Sendable (Date) -> InfluxDBClient.Point
    ) {
        if let (task, points) = timers[interval] {
            var points = points
            points[id] = point
            timers[interval] = (task, points)
        } else {
            let task = Task { [weak self] in
                let intervalInNanoSeconds = UInt64(interval * 1_000_000_000)
                var i: UInt64 = 0
                while !Task.isCancelled {
                    let date = Date(timeIntervalSince1970: startTime.timeIntervalSince1970 + Double(i) * interval)
                    Task { [weak self] in
                        if let points = await self?.timerPoints(interval: interval) {
                            for point in points {
                                try Task.checkCancellation()
                                await self?.add(point: point(date))
                            }
                        }
                    }
                    try await Task.sleep(nanoseconds: intervalInNanoSeconds)
                    i += 1
                }
            }
            timers[interval] = (task, [id: point])
        }
    }

    func removeFromTimer(interval: TimeInterval, id: UUID) {
        if let (task, points) = timers[interval] {
            var points = points
            points.removeValue(forKey: id)
            if points.isEmpty {
                task.cancel()
                timers.removeValue(forKey: interval)
            } else {
                timers[interval] = (task, points)
            }
        }
    }

    private func timerPoints(interval: TimeInterval) -> [(Date) -> InfluxDBClient.Point] {
        timers[interval]?.1.map(\.value) ?? []
    }

    private func writeIfNeeded() async {
        guard !points.isEmpty else { return }
        if points.count >= configs.batchSize {
            writeTask?.cancel()
            await write()
        } else if writeTask == nil {
            writeTask = Task { [weak self, configs] in
                try await Task.sleep(nanoseconds: UInt64(configs.throttleInterval) * 1_000_000_000)
                await self?.write()
            }
        }
    }

    private func write() async {
        writeTask = nil
        var points = self.points
        let largerThanBatch = points.count > configs.batchSize
        self.points.removeAll(keepingCapacity: !largerThanBatch)
        if largerThanBatch {
            self.points.reserveCapacity(configs.batchSize)
        }
        do {
            while !points.isEmpty {
                let batch = Array(points[0 ..< min(configs.batchSize, points.count)])
                try await client.makeWriteAPI()
                    .write(
                        bucket: configs.bucket,
                        org: configs.org,
                        precision: configs.precision,
                        points: batch,
                        responseQueue: responsesQueue
                    )
                points.removeFirst(batch.count)
            }
        } catch {
            self.points = points + self.points
//            Logger(label: "SwiftInfluxDBMetric")
//                .error("Failed to write points: \(error)")
        }
    }
}

private extension InfluxDBClient.Point.FieldValue {
    
    var string: String {
        switch self {
        case .boolean(let value):
            return value.description
        case .double(let value):
            return value.description
        case .int(let value):
            return value.description
        case .string(let value):
            return value
        case .uint(let value):
            return value.description
        }
    }
}

