import Foundation

public enum MetricIdentifyingPolicy: String, Hashable, Sendable {

    case byLabel, byLabelAndDimensions
}
