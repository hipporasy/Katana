/// Marks a type as resolvable by the `Container`. The macro inspects the type's
/// primary initializer and synthesizes an `Injectable` conformance whose
/// `resolve(from:)` method asks the container for each dependency in order.
///
/// ```swift
/// @Injectable
/// final class AuthService: Sendable {
///     init(network: NetworkService, logger: LoggerService) { ... }
/// }
/// ```
///
/// Pass `scope: .transient` to opt out of singleton caching. Singleton-scoped
/// types must be `Sendable`; transient types may be non-`Sendable`.
@attached(extension, conformances: Injectable, names: named(resolve), named(scope))
public macro Injectable(scope: Scope = .singleton) =
    #externalMacro(module: "KatanaMacros", type: "InjectableMacro")

/// Marks a class as a typed dependency-graph container. The macro reads the
/// listed types, emits typed `resolve(_:)` overloads (compile-checked against
/// the type list), and generates a nested `Snapshot` resolver plus a nested
/// `@Inject` property wrapper for SwiftUI.
///
/// ```swift
/// @Container(Logger.self, TodoRepository.self, TodoListViewModel.self)
/// final class App {}
///
/// let app = await App()
/// let vm = await app.resolve(TodoListViewModel.self)   // compile-checked
/// let snap = await app.snapshot()                       // App.Snapshot
///
/// struct ContentView: View {
///     @App.Inject var viewModel: TodoListViewModel
///     var body: some View { Text("\(viewModel.todos.count)") }
/// }
/// ```
///
/// Pass a closure to `init` for one-shot overrides — useful in tests:
///
/// ```swift
/// let app = await App { c in
///     await c.override(Logger.self, with: SpyLogger())
/// }
/// ```
@attached(member, names: arbitrary)
public macro Container(_ types: any (Injectable & Sendable).Type...) =
    #externalMacro(module: "KatanaMacros", type: "ContainerMacro")

/// `@TestContainer` is the test-target peer of `@Container`. It emits the
/// same shape — typed `resolve(_:)` overloads, nested `Snapshot`, nested
/// `Inject` — plus post-construction `override(_:with:)` / `override(_:factory:)`
/// methods and a `TestContainerMarker` conformance for tooling.
///
/// The type list is duplicated from the production `@Container`; Swift macros
/// can't read another declaration's annotation arguments across files. Diff
/// review or a small lint script keeps them in sync.
///
/// ```swift
/// @TestContainer(Logger.self, TodoRepository.self, TodoListViewModel.self)
/// final class TestApp {}
///
/// @Test func togglesCompletion() async {
///     let app = await TestApp()
///     await app.override(Logger.self, with: SpyLogger())
///     let vm = await app.resolve(TodoListViewModel.self)
///     // ...
/// }
/// ```
@attached(member, names: arbitrary)
@attached(extension, conformances: TestContainerMarker)
public macro TestContainer(_ types: any (Injectable & Sendable).Type...) =
    #externalMacro(module: "KatanaMacros", type: "TestContainerMacro")
