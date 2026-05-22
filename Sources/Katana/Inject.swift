#if canImport(SwiftUI)
import SwiftUI

/// Reads a dependency from a `Resolver` installed in the SwiftUI environment.
///
/// ```swift
/// struct ContentView: View {
///     @Inject var viewModel: TodoListViewModel        // .default scope
///     @Inject(\.checkout) var cart: CartStore         // explicit scope
/// }
/// ```
///
/// The bare `init()` overload is emitted by the `KatanaCodegen` build plugin
/// only when the target has exactly one `@Container(scope: .default, …)`.
/// Without it, bare `@Inject` fails to compile.
@propertyWrapper
public struct Inject<Value: Sendable>: DynamicProperty {
    private var resolver: Environment<(any Resolver)?>

    public init(_ keyPath: KeyPath<EnvironmentValues, (any Resolver)?>) {
        self.resolver = Environment(keyPath)
    }

    public var wrappedValue: Value {
        guard let resolver = resolver.wrappedValue else {
            preconditionFailure(
                "@Inject: no Snapshot installed in the environment at the requested scope. "
                + "Install one at the composition root via `.katana(snapshot)`."
            )
        }
        return resolver.resolve(Value.self)
    }
}
#endif
