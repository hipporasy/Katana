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

/// Declares a typed dependency-graph class. The `KatanaCodegen` build plugin
/// aggregates types from the listed `@Module`s and emits the typed API:
/// `init(_:) async`, per-type `resolve(_:) async` overloads, nested
/// `Snapshot`, `snapshot() async`, the matching `EnvironmentValues` slot, and
/// a `View.katana(_:)` install modifier.
///
/// ```swift
/// @Module(Logger.self, AnalyticsClient.self)
/// enum ServiceModule {}
///
/// @Container(modules: [ServiceModule.self])
/// final class App {}
///
/// struct ContentView: View {
///     @Inject var logger: Logger
/// }
/// ```
///
/// Declare additional scopes with `@Scope`:
///
/// ```swift
/// @Scope enum AppScope { case checkout }
///
/// @Container(scope: .checkout, modules: [CheckoutModule.self])
/// final class CheckoutGraph {}
///
/// struct CheckoutView: View {
///     @Inject(\.checkout) var vm: CheckoutViewModel
/// }
/// ```
///
/// Requires the `KatanaCodegenPlugin` SwiftPM plugin on the target.
@attached(member, names: arbitrary)
public macro Container(scope: ContainerScope = .default, modules: [any KatanaModule.Type]) =
    #externalMacro(module: "KatanaMacros", type: "ContainerMacro")

/// Test peer of `@Container`. Emits the same shape plus post-construction
/// `override(_:with:) async` / `override(_:factory:) async` methods and a
/// `TestContainerMarker` conformance.
///
/// ```swift
/// @TestContainer(modules: [TestAppModule.self])
/// final class TestApp {}
///
/// @Test func togglesCompletion() async {
///     let app = await TestApp { c in
///         await c.override(Logger.self, with: SpyLogger())
///     }
///     let vm = await app.resolve(TodoListViewModel.self)
/// }
/// ```
@attached(member, names: arbitrary)
@attached(extension, conformances: TestContainerMarker)
public macro TestContainer(scope: ContainerScope = .default, modules: [any KatanaModule.Type]) =
    #externalMacro(module: "KatanaMacros", type: "TestContainerMacro")

/// Groups injectable types into a named module so they can be aggregated from
/// `@Container(modules: [...])`. Emits a `static let types` array and a
/// `KatanaModule` conformance.
///
/// ```swift
/// @Module(TodoRepository.self, UserRepository.self)
/// enum RepositoryModule {}
/// ```
@attached(member, names: named(types))
@attached(extension, conformances: KatanaModule)
public macro Module(_ types: any (Injectable & Sendable).Type...) =
    #externalMacro(module: "KatanaMacros", type: "ModuleMacro")

/// Declares a registry of custom container scopes. Each enum case becomes a
/// `static let` on `ContainerScope`, usable as `@Container(scope: .<case>, …)`
/// and `@Inject(\.<case>) var x: T`.
///
/// The macro emits only the `KatanaScope` marker conformance — the
/// `ContainerScope` static properties are emitted by the `KatanaCodegen`
/// build plugin.
///
/// ```swift
/// @Scope
/// enum AppScope {
///     case checkout
///     case payment
/// }
/// ```
///
/// Cases with associated values are rejected. Requires the
/// `KatanaCodegenPlugin` on the target.
@attached(extension, conformances: KatanaScope)
public macro Scope() =
    #externalMacro(module: "KatanaMacros", type: "ScopeMacro")
