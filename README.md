# Katana

A Swift 6 macro-based dependency injection framework. Dagger/Hilt semantics, Swift idioms, minimal runtime.

**[API Documentation →](https://katana.hipporasy.dev)** · **[Changelog →](CHANGELOG.md)**

```swift
@Injectable
final class AuthService: Sendable {
    init(network: NetworkService, logger: Logger) { … }
}

@Module(AuthService.self, NetworkService.self, Logger.self)
enum AuthModule {}

@Container(modules: [AuthModule.self])
final class App {}

let app = await App()
let auth = await app.resolve(AuthService.self)        // compile-checked
```

The macros generate every wiring detail. The `KatanaCodegen` build plugin aggregates `@Module`s, validates scope uniqueness, and emits typed `resolve(_:)` overloads, the typed `Snapshot`, the SwiftUI install modifier, and the bare `@Inject` default-init — all before compilation.

## Features

- **`@Injectable`** — annotate a type, the macro generates the container wiring. Compile-time only, no codegen step.
- **`@Module(T1.self, ...)`** — groups injectable types so they can be aggregated by name from any `@Container`.
- **`@Container(modules: [...])`** — declares a dependency graph by referencing one or more `@Module`s. The `KatanaCodegen` build plugin emits typed `resolve(_:)` overloads, the typed `Snapshot`, the install modifier, and the bare `@Inject` initializer for the `.default` scope.
- **`@TestContainer(modules: [...])`** — test-target peer with override-first ergonomics and `TestContainerMarker` conformance.
- **`@Scope`** — declares a registry of custom container scopes. Each enum case becomes `ContainerScope.<case>` for use in `@Container(scope: .X, …)` and `@Inject(\.X)`.
- **`@Inject` property wrapper** — bare form `@Inject var x: T` works in single-container targets; explicit form `@Inject(\.checkout) var x: T` targets a named scope. Type-safe via key paths; typos are compile errors.
- **Actor-based runtime** — `Container` is an `actor`; thread safety enforced by Swift's type system, no `@unchecked Sendable` workarounds.
- **Two scopes** — `.singleton` (cached, `Sendable` required) and `.transient` (`sending`-transferred ownership for non-`Sendable` types).
- **Swift 6 strict concurrency** — `.swiftLanguageMode(.v6)`, builds clean with zero warnings.
- **`@Observable` / `@MainActor` friendly** — both are implicitly `Sendable`, so they slot in as singletons with no extra work.
- **Auto-resolve** — registered types' transitive dependencies are resolved automatically; no need to enumerate every leaf.

## Requirements

- Swift 6.2+ (uses `NonisolatedNonsendingByDefault` upcoming feature)
- macOS 13+, iOS 13+, tvOS 13+, watchOS 6+, macCatalyst 13+
- swift-syntax 600.0.0+

## Install

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hipporasy/Katana.git", from: "0.2.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["Katana"],
        plugins: ["KatanaCodegenPlugin"]   // ← required on every target using @Container
    ),
]
```

Then `import Katana`.

> The build plugin is mandatory. `@Container` only emits storage stubs at macro-expansion time; the typed API, the `EnvironmentValues` slot, and the install modifier are emitted by the plugin before compilation.

## Quick Start

Annotate the types you want to inject:

```swift
import Katana

@Injectable
final class Logger: Sendable {
    init() {}
    func log(_ msg: String) { print(msg) }
}

@Injectable
final class NetworkClient: Sendable {
    let logger: Logger
    init(logger: Logger) { self.logger = logger }
}

@Injectable
final class AuthService: Sendable {
    let network: NetworkClient
    let logger: Logger
    init(network: NetworkClient, logger: Logger) {
        self.network = network
        self.logger = logger
    }
}
```

Group them into `@Module`s and aggregate into a `@Container`:

```swift
@Module(Logger.self, NetworkClient.self, AuthService.self)
enum AuthModule {}

@Container(modules: [AuthModule.self])
final class App {}

let app = await App()
let auth = await app.resolve(AuthService.self)        // OK
// let bad = await app.resolve(URLSession.self)         // compile error
```

For ad-hoc or dynamic scenarios the bare `Container` actor still works:

```swift
let container = Container()
await container.register(Logger.self)
await container.register(NetworkClient.self)
await container.register(AuthService.self)
let auth = await container.resolve(AuthService.self)
```

Both `register` and `resolve` are `async` because `Container` is an actor — no escape hatches.

## Scopes (injectable scope)

`@Injectable` controls how the container caches an instance — separate concept from `@Container`'s graph scope (see below).

### Singleton (default)

The container caches the instance and returns the same reference on every resolve. The type **must be `Sendable`**.

```swift
@Injectable                        // singleton by default
@Injectable(scope: .singleton)     // explicit

final class NetworkService: Sendable { … }
@Observable final class AppState { … }        // implicitly Sendable
@MainActor final class ViewModel { … }        // implicitly Sendable
```

### Transient

Each resolve creates a new instance. The container transfers ownership to the caller via `sending` (SE-0430), so the type does **not** need to be `Sendable`.

```swift
@Injectable(scope: .transient)
final class RequestContext { … }  // non-Sendable is fine
```

## SwiftUI integration — `@Inject`

`@Container` emits a `View.katana(_:)` install modifier and an `EnvironmentValues` slot per graph. Bare `@Inject var x: T` reads the default graph; `@Inject(\.<scope>)` selects a named one.

```swift
@Container(modules: [AppModule.self])
final class App {}

@main
struct MyApp: SwiftUI.App {
    @State private var snapshot: App.Snapshot?
    var body: some Scene {
        WindowGroup {
            if let snapshot {
                RootView().katana(snapshot)      // overload picked by snapshot type
            } else {
                ProgressView().task { snapshot = await App().snapshot() }
            }
        }
    }
}

struct ContentView: View {
    @Inject var viewModel: TodoListViewModel    // bare — default scope
    var body: some View { Text("\(viewModel.todos.count)") }
}
```

`App.snapshot()` eagerly resolves every registered singleton into a typed `App.Snapshot`. The plugin emits `Inject.init()` reading from `\.katanaDefault`, so SwiftUI views never touch the container directly. **One install at the root, infinite reads, zero per-view-model wiring.**

## Multiple graphs — `@Scope` + custom scopes

Declare additional scopes once; assign each to a `@Container`. `@Inject(\.<scope>)` reads from the matching graph.

```swift
@Scope
enum AppScope {
    case checkout
    case account
}

@Container(modules: [AppModule.self])
final class App {}                                         // .default → bare @Inject

@Container(scope: .checkout, modules: [CheckoutModule.self])
final class CheckoutGraph {}

struct CheckoutView: View {
    @Inject var session: AuthSession                       // from App
    @Inject(\.checkout) var vm: CheckoutViewModel          // from CheckoutGraph
}
```

The build plugin validates scope uniqueness across the target — two `@Container`s at the same scope is a build error pointing at both declarations.

## Testing — `@TestContainer`

Production-side compile-time safety, override-first ergonomics for tests:

```swift
@Module(Logger.self, TodoRepository.self, TodoListViewModel.self)
enum TestAppModule {}

@TestContainer(modules: [TestAppModule.self])
final class TestApp {}

@Test func togglesCompletion() async {
    let app = await TestApp { c in
        await c.override(Logger.self, with: SpyLogger())
    }
    let vm = await app.resolve(TodoListViewModel.self)
    // ...
}

@Test func overridePostConstruction() async {
    let app = await TestApp()
    await app.override(Logger.self, with: SpyLogger())   // ← test-only method
    // ...
}
```

`@TestContainer` emits the same shape as `@Container` plus post-construction `override(_:with:)` / `override(_:factory:)` methods and a `TestContainerMarker` conformance for project lint ("no test containers outside `Tests/`"). See [`Documentation/mvvm.md`](Documentation/mvvm.md) for the full walkthrough and [`Documentation/multi-container.md`](Documentation/multi-container.md) for multi-graph apps.

## Custom Factories

Pass an explicit factory closure when the default macro-generated wiring doesn't fit (e.g., conditional construction, third-party types):

```swift
await container.register(Network.self) { container in
    await Network(config: container.resolve(Config.self))
}
```

The closure is `@Sendable` and may itself `await` further resolutions.

## Manual `Injectable` Conformance

Leaf types without injectable dependencies can conform manually instead of using the macro:

```swift
extension URLSession: Injectable {
    static func resolve(from container: Container) async -> sending Self {
        Self.shared as! Self
    }
}
```

## Macro Behavior

### `@Injectable`

| Input                                      | Output                                                                          |
|--------------------------------------------|---------------------------------------------------------------------------------|
| `@Injectable` on type with no `init` args  | `resolve` returns `Self()`                                                      |
| `@Injectable` on type with init args       | `await Self(label: container.resolve(Type.self), …)`                            |
| `@Injectable(scope: .transient)`           | Adds `static var scope: Scope { .transient }`                                   |
| Multiple designated `init`s                | Warning: picks the first; mark others `convenience` to silence                  |
| `@Injectable` on `protocol` / `enum` / extension | Compile-time error                                                          |
| `init` with variadic or `inout` parameters | Compile-time error                                                              |

### `@Container`, `@TestContainer`

| Input                                                  | Output                                                                          |
|--------------------------------------------------------|---------------------------------------------------------------------------------|
| `@Container(modules: [M.self, …])` on `final class App` | Macro: storage stub + designated init. Plugin emits async `init(_ customize:)`, typed `resolve(_:)` overloads, nested `Snapshot: Resolver`, `snapshot() async`, `EnvironmentValues.<scope>` slot, and `View.katana(_:)` install modifier overload |
| `@Container(scope: .X, modules: [...])`                | Same as above; binds the graph to scope `.X` (declared via `@Scope`)            |
| `@TestContainer(modules: [...])`                       | Same as `@Container` plus async `override(_:with:)` / `override(_:factory:)` and `TestContainerMarker` conformance |
| `@Container` without `modules:`                        | Compile-time error                                                              |
| Two `@Container`s at the same scope (per target)       | Plugin build error: `Scope .X is bound to multiple @Container declarations`     |
| `@Container(scope: .X)` where `.X` isn't declared      | Plugin build error: `@Container(scope: .X) references an undeclared scope`     |

### `@Module`, `@Scope`

| Input                                                  | Output                                                                          |
|--------------------------------------------------------|---------------------------------------------------------------------------------|
| `@Module(T1.self, …)` on enum                          | Adds `static let types: [any (Injectable & Sendable).Type]` and `KatanaModule` conformance |
| `@Scope` on enum                                       | Adds `KatanaScope` conformance. Plugin emits one `static let <case> = ContainerScope("<case>")` per enum case on `ContainerScope` |
| `@Scope` case with associated values                   | Compile-time error                                                              |

## Concurrency Notes

- `Container` is an `actor`. All registration and resolution is `async`.
- The macro-generated `resolve(from:)` is `nonisolated` and `async`. With Swift 6.2's `NonisolatedNonsendingByDefault`, it runs on the caller's actor, so injecting `@MainActor` types or running inside other actors works without explicit hops.
- Factory closures stored by the container are not `@Sendable` — they only live inside the actor. User-supplied factory closures *are* `@Sendable` because they cross the actor boundary.
- The protocol's `resolve(from:) async -> sending Self` makes transient ownership-transfer the single uniform shape. For `Sendable` singletons, `sending` is a harmless no-op.

## Limitations

- A single designated `init` per type (multiple → first is used; warning emitted).
- No property injection — constructor injection only.
- Variadic and `inout` init parameters are rejected.
- **Plugin required.** `@Container` produces only storage stubs without `KatanaCodegenPlugin`; consumer sites fail to compile, surfacing the missing plugin.
- **Plugin is per-target.** Test targets that use `@testable import` to reach production types must re-declare their own `@Module` enums referencing those types. The scanner replays user imports in the generated file so `@testable import` lines propagate.
- **Named bindings are container-level only** — `register(_:name:)` and `resolve(_:name:)` work, but the macro path doesn't auto-handle them. For compile-time-safe disambiguation, prefer protocol abstractions or distinct `@Scope`s.
- **Cycle detection is runtime, not compile-time** — `Container.resolve` traps with a readable `A → B → A` chain on cycles. Compile-time cycle detection would require cross-file macro analysis and is out of scope.
- **Cycle detection on the non-`Sendable` transient resolve path is shallow** — cycles entering a transient resolve are caught, but the chain doesn't extend through them (Swift 6's sending-isolation analysis rejects the `withValue` wrap).
- `Container.snapshot()` includes only **unnamed** singletons. Named bindings remain accessible via `await container.resolve(_:name:)`.

## Examples

A full MVVM example — model, actor-backed repository, `@MainActor @Observable` view model, SwiftUI view with bare `@Inject`, and a Swift Testing suite that swaps deps per test — lives in [`Sources/Example/`](Sources/Example) with a walkthrough at [`Documentation/mvvm.md`](Documentation/mvvm.md).

```bash
swift run Example                  # runs the console driver
swift test --filter ExampleTests   # 19 Swift Testing cases: wiring, behaviour, overrides, named bindings, cycle detection
```

## Development

```bash
swift build                                    # Build all targets
swift test                                     # All macro + example tests
swift run KatanaClient                         # Runtime smoke test
swift run Example                              # MVVM example
swift test --filter KatanaTests/testEmptyInit  # Single test
```

The package has these SPM targets:

- `KatanaMacros` — the macro compiler plugin (runs at build time)
- `Katana` — the public library users import
- `KatanaCodegenCore` — scanner / emitter / validator backing the build plugin (testable)
- `KatanaCodegen` — thin executable wrapper invoked by the plugin
- `KatanaCodegenPlugin` — SwiftPM build-tool plugin powering `@Container` / `@TestContainer` / `@Scope`
- `KatanaClient` — runtime smoke test for `@Injectable` + bare `Container`
- `Example` — MVVM walk-through with `@Container(modules:)` + bare `@Inject`
- `ModularExample` — multi-module composition with a test container at a custom scope

Tests live in:

- `KatanaTests` — macro expansion via `assertMacroExpansion`
- `KatanaCodegenTests` — scanner / validator / emitter unit tests
- `ExampleTests` — Swift Testing suite exercising the example's container

## Design

See [`Documentation/design.md`](Documentation/design.md) for the architectural rationale and [`Documentation/swift6.md`](Documentation/swift6.md) for the Swift 6 concurrency rules the library is built on.

## License

MIT
