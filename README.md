# Katana

A Swift 6 macro-based dependency injection framework. Dagger/Hilt semantics, Swift idioms, minimal runtime.

**[API Documentation →](https://katana.hipporasy.dev)**

```swift
@Injectable
final class AuthService: Sendable {
    init(network: NetworkService, logger: Logger) { … }
}

let container = Container()
await container.register(AuthService.self)

let auth = await container.resolve(AuthService.self)
```

The `@Injectable` macro inspects the type's primary initializer and synthesizes the wiring; you never write factory boilerplate.

## Features

- **`@Injectable`** — annotate a type, the macro generates the container wiring. SwiftSyntax compiler plugin, no codegen step.
- **`@Container`** — declare your dependency graph in one place. The macro emits typed `resolve(_:)` overloads, so **resolving an unregistered type is a compile error**, not a runtime trap. Refactor-safe by construction.
- **`@TestContainer`** — test-target peer of `@Container` with override-first ergonomics and a `TestContainerMarker` conformance for project lint. Same compile-time safety.
- **`@<Graph>.Inject`** — typed SwiftUI property wrapper, generated per graph. One `.katana(snapshot)` install at the root, infinite `@App.Inject var x: T` reads anywhere — the Hilt `hiltViewModel()` equivalent for SwiftUI.
- **Actor-based runtime** — `Container` is an `actor`; thread safety is enforced by Swift's type system, no `@unchecked Sendable` workarounds.
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
    .package(url: "https://github.com/hipporasy/Katana.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["Katana"]),
]
```

Then `import Katana`.

## Quick Start

Annotate types you want to inject:

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

Declare the graph once with `@Container`. Resolves are compile-checked against the type list:

```swift
@Container(Logger.self, NetworkClient.self, AuthService.self)
final class App {}

let app = await App()
let auth = await app.resolve(AuthService.self)        // OK
// let bad = await app.resolve(URLSession.self)        // ❌ compile error
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

## Scopes

### Singleton (default)

The container caches the instance and returns the same reference on every resolve. The type **must be `Sendable`**.

```swift
@Injectable                        // singleton by default
@Injectable(scope: .singleton)     // explicit

final class NetworkService: Sendable { … }    // ✅
@Observable final class AppState { … }        // ✅ implicitly Sendable
@MainActor final class ViewModel { … }        // ✅ implicitly Sendable
```

### Transient

Each resolve creates a new instance. The container transfers ownership to the caller via `sending` (SE-0430), so the type does **not** need to be `Sendable`.

```swift
@Injectable(scope: .transient)
final class RequestContext { … }  // ✅ non-Sendable is fine
```

## SwiftUI integration — `@App.Inject`

For SwiftUI apps, declare your graph with `@Container`, snapshot it once at launch, install with one `.katana(...)` call, and let every view read dependencies with the macro-generated typed `@App.Inject`:

```swift
@Container(Logger.self, TodoRepository.self, TodoListViewModel.self)
final class App {}

@main
struct MyApp: SwiftUI.App {
    @State private var snapshot: App.Snapshot?
    var body: some Scene {
        WindowGroup {
            if let snapshot {
                RootView().katana(snapshot)
            } else {
                ProgressView().task { snapshot = await App().snapshot() }
            }
        }
    }
}

struct ContentView: View {
    @App.Inject var viewModel: TodoListViewModel   // compile-checked
    var body: some View { Text("\(viewModel.todos.count)") }
}
```

`App.snapshot()` eagerly resolves every registered singleton into the typed `App.Snapshot`. `@App.Inject` reads the snapshot from the environment and calls the typed `resolve(_:)` overload — resolving an unregistered type is a build error, not a runtime trap. **One install at the root, infinite reads, zero per-view-model wiring.**

## Testing — `@TestContainer`

Production-side compile-time safety, override-first ergonomics for tests:

```swift
@TestContainer(Logger.self, TodoRepository.self, TodoListViewModel.self)
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

| Input                                      | Output                                                                          |
|--------------------------------------------|---------------------------------------------------------------------------------|
| `@Injectable` on type with no `init` args  | `resolve` returns `Self()`                                                      |
| `@Injectable` on type with init args       | `await Self(label: container.resolve(Type.self), …)`                            |
| `@Injectable(scope: .transient)`           | Adds `static var scope: Scope { .transient }`                                   |
| Multiple designated `init`s                | Warning: picks the first; mark others `convenience` to silence                  |
| `@Injectable` on `protocol` / `enum` / extension | Compile-time error                                                          |
| `init` with variadic or `inout` parameters | Compile-time error                                                              |

Unlabeled parameters (`init(_ value: Foo)`), generic dependency types (`Store<User>`), and parameters with default values are all supported. Default values are ignored — every `init` parameter is resolved through the container.

## Concurrency Notes

- `Container` is an `actor`. All registration and resolution is `async`.
- The macro-generated `resolve(from:)` is `nonisolated` and `async`. With Swift 6.2's `NonisolatedNonsendingByDefault`, it runs on the caller's actor, so injecting `@MainActor` types or running inside other actors works without explicit hops.
- Factory closures stored by the container are not `@Sendable` — they only live inside the actor. User-supplied factory closures *are* `@Sendable` because they cross the actor boundary.
- The protocol's `resolve(from:) async -> sending Self` makes transient ownership-transfer the single uniform shape. For `Sendable` singletons, `sending` is a harmless no-op.

## Limitations (v1)

- A single designated `init` per type (multiple → first is used; warning emitted).
- No property injection — constructor injection only.
- No qualifiers / named bindings — one registration per type.
- Variadic and `inout` init parameters are rejected.
- No cycle detection at registration time (cycles in the dependency graph will hang at resolve time).

## Examples

A full MVVM example — model, actor-backed repository, `@MainActor @Observable` view model, SwiftUI view, and a Swift Testing suite that swaps the container per test — lives in [`Sources/Example/`](Sources/Example) with a walkthrough at [`Documentation/mvvm.md`](Documentation/mvvm.md).

```bash
swift run Example                  # runs the console driver
swift test --filter Example        # runs the 7 wiring / behaviour / swap-the-container tests
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

- `KatanaMacros` — the compiler plugin (runs at build time)
- `Katana` — the public library users import
- `KatanaClient` — runtime demo / smoke test
- `Example` — MVVM walk-through (executable + SwiftUI view + tests)

Tests live in `KatanaTests` (macro expansion via `assertMacroExpansion`) and `ExampleTests` (Swift Testing suite exercising the example's container).

## Design

See [`Documentation/design.md`](Documentation/design.md) for the architectural rationale and [`Documentation/swift6.md`](Documentation/swift6.md) for the Swift 6 concurrency rules the library is built on.

## License

MIT
