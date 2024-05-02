import Foundation
import InfluxDBSwift

package final actor SwiftInfluxAPI: Sendable {

    private static var cache: [String: SwiftInfluxAPI] = [:]

    package nonisolated let labelsAsTags: LabelsSet
    package nonisolated let client: InfluxDBClient
    package nonisolated let batchSize: Int
    package nonisolated let bucket: String
    package nonisolated let org: String
    package nonisolated let throttleInterval: UInt64
    package nonisolated let precision: InfluxDBClient.TimestampPrecision
    private let responsesQueue = DispatchQueue(label: "SwiftInfluxAPI.responsesQueue", qos: .background)
    private var points: [InfluxDBClient.Point]
    private var writeTask: Task<Void, Error>?

    package static func make(
        client: InfluxDBClient,
        bucket: String,
        org: String,
        precision: InfluxDBClient.TimestampPrecision,
        batchSize: Int,
        throttleInterval: UInt16,
        labelsAsTags: LabelsSet
    ) -> SwiftInfluxAPI {
        let key = client.url
        if let api = cache[key] {
            return api
        }
        let api = SwiftInfluxAPI(
            client: client,
            bucket: bucket,
            org: org,
            precision: precision,
            batchSize: batchSize,
            throttleInterval: UInt64(throttleInterval),
            labelsAsTags: labelsAsTags
        )
        cache[key] = api
        return api
    }

    private init(
        client: InfluxDBClient,
        bucket: String,
        org: String,
        precision: InfluxDBClient.TimestampPrecision,
        batchSize: Int,
        throttleInterval: UInt64,
        labelsAsTags: LabelsSet
    ) {
        self.client = client
        self.batchSize = batchSize
        self.bucket = bucket
        self.org = org
        self.precision = precision
        self.throttleInterval = throttleInterval
        var points: [InfluxDBClient.Point] = []
        points.reserveCapacity(batchSize)
        self.points = points
        self.labelsAsTags = labelsAsTags
    }

    nonisolated package func write(
        measurement: String,
        tags: [String: String],
        fields: [String: InfluxDBClient.Point.FieldValue],
        unspecified: [(String, InfluxDBClient.Point.FieldValue)]
    ) {
        Task {
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
            await self.add(point: point)
        }
    }

    private func add(point: InfluxDBClient.Point) async {
        points.append(point)
        await writeIfNeeded()
    }

    private func writeIfNeeded() async {
        guard !points.isEmpty else { return }
        if points.count >= batchSize {
            writeTask?.cancel()
            await write()
        } else if writeTask == nil {
            writeTask = Task { [weak self, throttleInterval] in
                try await Task.sleep(nanoseconds: throttleInterval * 1_000_000_000)
                await self?.write()
            }
        }
    }

    private func write() async {
        writeTask = nil
        var points = self.points
        let largerThanBatch = points.count > batchSize
        self.points.removeAll(keepingCapacity: !largerThanBatch)
        if largerThanBatch {
            self.points.reserveCapacity(batchSize)
        }
        do {
            while !points.isEmpty {
                let batch = Array(points[0 ..< min(batchSize, points.count)])
                try await client.makeWriteAPI()
                    .write(
                        bucket: bucket,
                        org: org,
                        precision: precision,
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

