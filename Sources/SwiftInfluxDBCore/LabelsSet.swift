import Foundation

/// A set of labels.
public struct LabelsSet: ExpressibleByArrayLiteral, Sendable {

    public static let empty = LabelsSet()
    public static let all = LabelsSet { _ in true }

    private var _contains: @Sendable (String) -> Bool

    public var inverted: LabelsSet {
        LabelsSet { [contains] in
            !contains($0)
        }
    }

    public init() {
        self.init { _ in false }
    }

    public init(_ contains: @escaping @Sendable (String) -> Bool) {
        self._contains = contains
    }

    public init(_ labels: some Collection<String>) {
        let set = Set(labels)
        self.init {
            set.contains($0)
        }
    }

    public init(arrayLiteral elements: String...) {
        self.init(elements)
    }
    
    public init(_ elements: String...) {
        self.init(elements)
    }

    public func contains(_ label: String) -> Bool {
        _contains(label)
    }

    public func union(_ other: __owned LabelsSet) -> LabelsSet {
        LabelsSet { [self, other] in
            self.contains($0) || other.contains($0)
        }
    }
    
    public func intersection(_ other: LabelsSet) -> LabelsSet {
        LabelsSet { [self, other] in
            self.contains($0) && other.contains($0)
        }
    }
    
    public func symmetricDifference(_ other: __owned LabelsSet) -> LabelsSet {
        LabelsSet { [self, other] in
            self.contains($0) != other.contains($0)
        }
    }

    public mutating func insert(_ newMember: __owned String) -> (inserted: Bool, memberAfterInsert: String) {
        _contains = { [contains = _contains] in
            contains($0) || $0 == newMember
        }
        return (true, newMember)
    }
    
    public mutating func remove(_ member: String) -> String? {
        guard contains(member) else {
            return nil
        }
        _contains = { [contains = _contains] in
            contains($0) && $0 != member
        }
        return member
    }

    public mutating func update(with newMember: __owned String) -> String? {
        guard !contains(newMember) else {
            return nil
        }
        _contains = { [contains = _contains] in
            contains($0) || $0 == newMember
        }
        return newMember
    }
    
    public mutating func formUnion(_ other: __owned LabelsSet) {
        self = union(other)
    }
    
    public mutating func formIntersection(_ other: LabelsSet) {
        self = intersection(other)
    }
    
    public mutating func formSymmetricDifference(_ other: __owned LabelsSet) {
        self = symmetricDifference(other)
    }
}
