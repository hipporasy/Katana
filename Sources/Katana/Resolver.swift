/// A synchronous, immutable view of singletons resolved from a `Container`.
///
/// `Resolver` is a protocol so the `@Container` macro can emit a typed
/// resolver per dependency graph with compile-time-checked overloads, while
/// generic SwiftUI code (`@Inject`, view modifiers) continues to work against
/// `any Resolver`.
///
/// Build one with ``Container/snapshot()`` and pass it down — typically via
/// SwiftUI's environment so views can read dependencies with `@Inject` instead
/// of awaiting the container on every access.
///
/// ```swift
/// let container = await makeAppContainer()
/// let resolver = await container.snapshot()
///
/// // In SwiftUI:
/// RootView().katana(resolver)
///
/// // In any descendant view:
/// @Inject var viewModel: TodoListViewModel
/// ```
public protocol Resolver: Sendable {
    /// Returns the pre-resolved singleton of type `T`. Implementations trap
    /// when `T` was not part of the snapshot.
    func resolve<T: Sendable>(_ type: T.Type) -> T
}

/// Type-erased `Resolver` backed by an `ObjectIdentifier` dictionary.
///
/// `Container.snapshot()` returns this for runtime/dynamic use. The `@Container`
/// macro emits a nested typed `Snapshot` struct that conforms to `Resolver`
/// directly and adds typed `resolve(_:)` overloads on top — that path catches
/// unregistered types at compile time.
public struct AnyResolver: Resolver {
    @usableFromInline let storage: [ObjectIdentifier: any Sendable]

    init(_ storage: [ObjectIdentifier: any Sendable]) {
        self.storage = storage
    }

    @inlinable
    public func resolve<T: Sendable>(_ type: T.Type) -> T {
        guard let value = storage[ObjectIdentifier(type)] as? T else {
            preconditionFailure(
                "\(type) is not in this Resolver. Register it with the container before calling snapshot(), or use a typed @Container's Snapshot for compile-time safety."
            )
        }
        return value
    }
}

// Convenience overload mirrors the prior concrete API so call sites that wrote
// `resolver.resolve(Foo.self)` continue to work uniformly across `AnyResolver`
// and macro-generated typed resolvers.
extension Resolver {
    @inlinable
    public func resolve<T: Sendable>() -> T {
        resolve(T.self)
    }
}
