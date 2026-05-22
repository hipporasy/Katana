/// Identifies a dependency-graph scope. `@Container(scope:)` tags a graph with
/// a `ContainerScope`; `@Inject(\.<name>)` reads the matching snapshot from
/// the SwiftUI environment.
///
/// `.default` is built in. Declare custom scopes with `@Scope`:
///
/// ```swift
/// @Scope
/// enum AppScope {
///     case checkout
///     case payment
/// }
/// ```
public struct ContainerScope: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public static let `default` = ContainerScope("default")
}

/// Marker conformance attached by `@Scope` to the annotated enum.
public protocol KatanaScope {}
