import Foundation
@_exported import InfluxDBSwift
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif
import Logging

public struct BucketWriterOptions: @unchecked Sendable {

	public let client: InfluxDBClient
	public var bucket: String
	public var org: String
	public var batchSize: Int
	public var throttleInterval: UInt16
	public var errorPolicy: ErrorPolicy

	/// Create a new `BucketWriterOptions`.
	/// - Parameters:
	///   - client: The InfluxDB client to use.
	///   - org: The InfluxDB organization.
	///   - bucket: The InfluxDB bucket.
	///   - batchSize: The maximum number of points to batch before writing to InfluxDB. Defaults to 5000.
	///   - throttleInterval: The maximum number of seconds to wait before writing a batch of points. Defaults to 5.
	///   - errorPolicy: The error policy to use. Defaults to `.tryLater`.
	public init(
		client: InfluxDBClient,
		org: String,
		bucket: String,
		batchSize: Int = 5000,
		throttleInterval: UInt16 = 5,
		errorPolicy: ErrorPolicy = .tryLater
	) {
		self.client = client
		self.bucket = bucket
		self.org = org
		self.batchSize = batchSize
		self.throttleInterval = throttleInterval
		self.errorPolicy = errorPolicy
	}

	/// Create a new `BucketWriterOptions`.
	///
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
	///   - errorPolicy: The error policy to use. Defaults to `.tryLater`.
	///   - enableGzip: Enable Gzip compression for HTTP requests.
	///   - connectionProxyDictionary: Enable Gzip compression for HTTP requests.
	///   - urlSessionDelegate: A delegate to handle HTTP session-level events.
	///   - debugging: optional Enable debugging for HTTP request/response. Default `false`.
	///   - protocolClasses: optional array of extra protocol subclasses that handle requests.
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
		errorPolicy: ErrorPolicy = .tryLater,
		enableGzip: Bool = false,
		connectionProxyDictionary: [AnyHashable: Any]? = nil,
		urlSessionDelegate: URLSessionDelegate? = nil,
		debugging: Bool? = nil,
		protocolClasses: [AnyClass]? = nil
	) {
		self.init(
			client: InfluxDBClient(
				url: url,
				token: token,
				options: InfluxDBClient.InfluxDBOptions(
					precision: precision,
					timeoutIntervalForRequest: timeoutIntervalForRequest,
					timeoutIntervalForResource: timeoutIntervalForResource,
					enableGzip: enableGzip,
					connectionProxyDictionary: connectionProxyDictionary,
					urlSessionDelegate: urlSessionDelegate
				),
				debugging: debugging,
				protocolClasses: protocolClasses
			),
			org: org,
			bucket: bucket,
			errorPolicy: errorPolicy
		)
	}

	/// Create a new `BucketWriterOptions`.
	///
	/// - Parameters:
	///   - url: InfluxDB host and port.
	///   - username: Username for authentication.
	///   - password: Password for authentication
	///   - org: The InfluxDB organization.
	///   - database: Target database.
	///   - retentionPolicy: Target retention policy.
	///   - bucket: The InfluxDB bucket.
	///   - precision: Precision for the unix timestamps within the body line-protocol.
	///   - batchSize: The maximum number of points to batch before writing to InfluxDB. Defaults to 5000.
	///   - throttleInterval: The maximum number of seconds to wait before writing a batch of points. Defaults to 5.
	///   - timeoutIntervalForRequest: Timeout interval to use when waiting for additional data.
	///   - timeoutIntervalForResource: Maximum amount of time that a resource request should be allowed to take.
	///   - errorPolicy: The error policy to use. Defaults to `.tryLater`.
	///   - enableGzip: Enable Gzip compression for HTTP requests.
	///   - connectionProxyDictionary: Enable Gzip compression for HTTP requests.
	///   - urlSessionDelegate: A delegate to handle HTTP session-level events.
	///   - debugging: optional Enable debugging for HTTP request/response. Default `false`.
	///   - protocolClasses: optional array of extra protocol subclasses that handle requests.
	public init(
		url: String,
		username: String,
		password: String,
		org: String,
		database: String,
		retentionPolicy: String,
		precision: InfluxDBClient.TimestampPrecision = InfluxDBClient.defaultTimestampPrecision,
		batchSize: Int = 5000,
		throttleInterval: UInt16 = 5,
		timeoutIntervalForRequest: TimeInterval = 60,
		timeoutIntervalForResource: TimeInterval = 60 * 5,
		errorPolicy: ErrorPolicy = .tryLater,
		enableGzip: Bool = false,
		connectionProxyDictionary: [AnyHashable: Any]? = nil,
		urlSessionDelegate: URLSessionDelegate? = nil,
		debugging: Bool? = nil,
		protocolClasses: [AnyClass]? = nil
	) {
		self.init(
			url: url,
			token: "\(username):\(password)",
			org: org,
			bucket: "\(database)/\(retentionPolicy)",
			precision: precision,
			batchSize: batchSize,
			throttleInterval: throttleInterval,
			timeoutIntervalForRequest: timeoutIntervalForRequest,
			timeoutIntervalForResource: timeoutIntervalForResource,
			errorPolicy: errorPolicy,
			enableGzip: enableGzip,
			connectionProxyDictionary: connectionProxyDictionary,
			urlSessionDelegate: urlSessionDelegate,
			debugging: debugging,
			protocolClasses: protocolClasses
		)
	}

	public enum ErrorPolicy: Sendable {

		/// Try to write the data later. The batches  limit is the maximum number of batches to keep in memory.
		case tryLater(batchesLimit: Int)
		/// Skip the data and continue.
		case skip

		public static var tryLater: Self { .tryLater(batchesLimit: 5) }
	}
}

package struct InfluxDBWriter: InfluxDBPointsWriter {

	package static let loggerLabel = "swift-influxdb-telemetry"

	package let intervalType: IntervalType
	private let api: SwiftInfluxAPI

	package init(
		options: BucketWriterOptions,
		intervalType: IntervalType = .irregular
	) {
		self.intervalType = intervalType
		api = .make(options: options)
	}

	package func load(
		measurement: String,
		tags: [String: String],
		fields: Set<String>
	) async throws -> QueryAPI.FluxRecord? {
		try await api.load(measurement: measurement, tags: tags, fields: fields)
	}
	
	package func write(
		point: InfluxDBClient.Point,
		measurementID: UUID
	) {
		let date = Date()
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

	package func flush() {
		Task {
			await api.writeIfNeeded(force: true)
		}
	}
}

private final actor SwiftInfluxAPI: Sendable {

	private static let cache = NIOLockedValueBox([BatcherID: SwiftInfluxAPI]())

	private let options: BucketWriterOptions
	private let responsesQueue: DispatchQueue
	private var points: [InfluxDBClient.Point]
	private var writeTask: Task<Void, Error>?
	private var timers: [TimeInterval: (Task<Void, Error>, [UUID: (Date) -> InfluxDBClient.Point])] = [:]

	static func make(options: BucketWriterOptions) -> SwiftInfluxAPI {
		cache.withLockedValue { cache in
			let key = BatcherID(url: options.client.url, bucket: options.bucket, org: options.org)
			if let api = cache[key] {
				return api
			}
			let api = SwiftInfluxAPI(options: options)
			cache[key] = api
			return api
		}
	}

	private init(options: BucketWriterOptions) {
		self.options = options
		var points: [InfluxDBClient.Point] = []
		points.reserveCapacity(options.batchSize)
		self.points = points
		responsesQueue = DispatchQueue(label: "InfluxDB.\(options.org).\(options.bucket)", qos: .background)
	}

	func load(
		measurement: String,
		tags: [String: String],
		fields: Set<String>
	) async throws -> QueryAPI.FluxRecord? {
		let filter = ([("_measurement", measurement)] + tags.sorted(by: { $0.key < $1.key }) + fields.map { ("_field", $0) })
			.map { "  |> filter(fn: (r) => r.\($0.key) == \"\($0.value)\")" }
			.joined(separator: "\n")

		return try await options.client.queryAPI.query(
			query: """
			from(bucket: "\(options.bucket)")
			  |> range(start: -30d)
			\(filter)
			  |> last()
			""",
			org: options.org,
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
				let offset = (startTime.timeIntervalSince1970 / interval).rounded(.down) * interval
				let intervalInNanoSeconds = UInt64(interval * 1_000_000_000)
				var i: UInt64 = 0
				while !Task.isCancelled {
					let j = i
					Task { [weak self] in
						try await self?.writeTimerPoints(
							date: Date(timeIntervalSince1970: offset + Double(j) * interval),
							interval: interval
						)
					}
					try await Task.sleep(nanoseconds: intervalInNanoSeconds)
					i &+= 1
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

	private func writeTimerPoints(date: Date, interval: TimeInterval) async throws {
		guard let points = timers[interval]?.1.values else { return }
		for point in points {
			try Task.checkCancellation()
			await add(point: point(date))
		}
	}

	func writeIfNeeded(force: Bool = false) async {
		guard !points.isEmpty else { return }
		if points.count >= options.batchSize || force {
			writeTask?.cancel()
			await write()
		} else if writeTask == nil {
			writeTask = Task { [weak self, options] in
				try await Task.sleep(nanoseconds: UInt64(options.throttleInterval) * 1_000_000_000)
				await self?.write()
			}
		}
	}

	private func write() async {
		writeTask = nil
		var points = points
		let largerThanBatch = points.count > options.batchSize
		self.points.removeAll(keepingCapacity: !largerThanBatch)
		if largerThanBatch {
			self.points.reserveCapacity(options.batchSize)
		}
		do {
			while !points.isEmpty {
				let batch = Array(points[0 ..< min(options.batchSize, points.count)])
				try await options.client.makeWriteAPI()
					.write(
						bucket: options.bucket,
						org: options.org,
						points: batch,
						responseQueue: responsesQueue
					)
				points.removeFirst(batch.count)
			}
		} catch {
			switch options.errorPolicy {
			case let .tryLater(batchesLimit):
				self.points = points.suffix(max(0, (batchesLimit * options.batchSize) - self.points.count)) + self.points
			case .skip:
				break
			}
			let logger = Logger(label: InfluxDBWriter.loggerLabel)
			switch error {
			case let InfluxDBClient.InfluxDBError.error(code, _, body, _):
				switch code {
				case 413: // Request Entity Too Large
					logger.error("InfluxDB error: `Request Entity Too Large: \(body?.description ?? "")`")
				case 429: // Too Many Requests
					logger.error("InfluxDB error: `Too Many Requests: \(body?.description ?? "")`")
				default:
					logger.error("InfluxDB error: `Code: \(code), body: \(body?.description ?? "")`")
				}
			default:
				logger.error("InfluxDB error: `\(error)`")
			}
		}
	}
}

package extension InfluxDBClient.Point.FieldValue {

	var string: String {
		switch self {
		case let .boolean(value):
			return value.description
		case let .double(value):
			return value.description
		case let .int(value):
			return value.description
		case let .string(value):
			return value
		case let .uint(value):
			return value.description
		}
	}
}

private struct BatcherID: Hashable {

	let url: String
	var bucket: String
	var org: String
}
