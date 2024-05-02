@usableFromInline
package struct NIOLockedValueBox<Value> {
    
    @usableFromInline
    internal let _storage: LockStorage<Value>
    
    /// Initialize the `Value`.
    @inlinable
    package init(_ value: Value) {
        self._storage = .create(value: value)
    }
    
    /// Access the `Value`, allowing mutation of it.
    @inlinable
    package func withLockedValue<T>(_ mutate: (inout Value) throws -> T) rethrows -> T {
        return try self._storage.withLockedValue(mutate)
    }
}

extension NIOLockedValueBox: Sendable where Value: Sendable {}
