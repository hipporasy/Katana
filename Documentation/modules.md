# `@Module` — module composition

Katana declares a dependency graph by aggregating one or more `@Module` enums into a `@Container`. The `KatanaCodegen` SwiftPM build plugin scans the target, validates the graph, and emits the typed API before compilation.

## Quick tour

```swift
// Modules/ServiceModule.swift
@Module(Logger.self, AnalyticsClient.self)
enum ServiceModule {}

// Modules/RepositoryModule.swift
@Module(TodoRepository.self, UserRepository.self)
enum RepositoryModule {}

// Modules/ViewModelModule.swift
@available(macOS 14, iOS 17, *)
@Module(TodoListViewModel.self)
enum ViewModelModule {}

// App.swift
@available(macOS 14, iOS 17, *)
@Container(modules: [
    ServiceModule.self,
    RepositoryModule.self,
    ViewModelModule.self,
])
final class App {}
```

The build plugin scans the target, aggregates the type lists across files, and emits an `extension App` with:

- `init(_:) async` taking an optional override closure
- `resolve(_:) async` overload per registered type
- `App.Snapshot` (typed, `Sendable`)
- `snapshot() async -> Snapshot`
- `EnvironmentValues.katanaDefault: (any Resolver)?`
- `View.katana(_ snapshot: App.Snapshot) -> some View`
- `extension Inject { init() }` (only because `App` is the target's single `.default`-scoped container)

After build:

```swift
let app = await App()
let repo = await app.resolve(TodoRepository.self)    // compile-checked
let bad = await app.resolve(URLSession.self)         // compile error
let snap = await app.snapshot()                       // App.Snapshot
```

## Enabling the plugin in your `Package.swift`

The plugin is **mandatory** on every target that uses `@Container`:

```swift
.executableTarget(
    name: "MyApp",
    dependencies: ["Katana"],
    plugins: ["KatanaCodegenPlugin"]   // ← required
)
```

Without it, only the macro's storage stub exists and every call site that expects `resolve(_:)`, `snapshot()`, etc. fails to compile, surfacing the missing plugin.

## SwiftUI integration

The plugin generates a typed env key per scope. Bare `@Inject` reads the `.default` graph; explicit `@Inject(\.<scope>)` reads named scopes.

```swift
@main
struct MyApp: SwiftUI.App {
    @State private var snapshot: App.Snapshot?

    var body: some Scene {
        WindowGroup {
            if let snapshot {
                ContentView().katana(snapshot)             // ← overload picked by snapshot type
            } else {
                ProgressView().task { snapshot = await App().snapshot() }
            }
        }
    }
}

struct ContentView: View {
    @Inject var repo: TodoRepository                       // ← bare, compile-checked
    var body: some View { /* ... */ }
}
```

For multiple graphs in the same app, declare a `@Scope` and bind each `@Container` to a case:

```swift
@Scope
enum AppScope { case checkout }

@Container(modules: [...])
final class App {}                                         // .default

@Container(scope: .checkout, modules: [...])
final class Checkout {}

// Plugin generates:
//   - \.katanaDefault, .katana(_:App.Snapshot), bare @Inject
//   - \.checkout,      .katana(_:Checkout.Snapshot), @Inject(\.checkout)
//
// They're independent — `@Inject var x: T` reads App; `@Inject(\.checkout) var y: U` reads Checkout.
```

## Testing — `@TestContainer`

The test peer reads its own module list and emits the same shape plus `override(_:with:) async`, `override(_:factory:) async`, and `TestContainerMarker` conformance:

```swift
@TestContainer(modules: [TestAppModule.self])
final class TestApp {}

@Test func usesSpyLogger() async {
    let spy = SpyLogger()
    let app = await TestApp { c in
        await c.override(Logger.self, with: spy)
    }
    let vm = await app.resolve(SomeViewModel.self)
    // ...
}

@Test func overridePostConstruction() async {
    let app = await TestApp()
    let spy = SpyLogger()
    await app.override(Logger.self, with: spy)
    // ...
}
```

`@TestContainer` requires the plugin on the test target:

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: ["MyApp", "Katana"],
    plugins: ["KatanaCodegenPlugin"]
)
```

### Cross-target imports

The plugin scans per target. If a test target uses `@testable import MyApp` to reach internal production types, the scanner records that import and the emitter replays it in the generated file:

```swift
// Generated KatanaGenerated.swift for the test target:
import Katana
@testable import MyApp

extension TestApp { ... }
```

Re-declare the `@Module` enums in the test target (referencing the production types). The production target's `@Module` enums aren't visible to the plugin's per-target scan.

To avoid `EnvironmentValues.katanaDefault` colliding between production and test targets (both at `.default`), put `@TestContainer` on a custom scope:

```swift
@Scope enum AppTestsScope { case test }
@TestContainer(scope: .test, modules: [TestAppModule.self]) final class TestApp {}
```

The test target's `TestApp` now binds to `.test` (its own env slot). Tests use `app.resolve(...)` and `app.override(...)` directly — they don't go through SwiftUI's environment.

## How the plugin works

`KatanaCodegen` is a SwiftPM build-tool plugin that runs once per target before compilation. It:

1. Parses every `.swift` file in the target with SwiftSyntax (read-only — no source modification).
2. Collects:
   - `@Module(...)` declarations (name + type list)
   - `@Container(scope:, modules:)` / `@TestContainer(scope:, modules:)` declarations (name + scope + module references)
   - `@Scope` enum declarations (case names → become `ContainerScope` statics)
   - `import` / `@testable import` declarations (replayed in the generated file)
3. Validates:
   - No type registered in two different `@Module` enums
   - Every module reference resolves to a discovered `@Module`
   - Every scope reference is `.default` or declared by some `@Scope`
   - At most one `@Container` per scope per target
4. Emits a single `KatanaGenerated.swift` file in the build directory containing:
   - The collected user imports (so the generated file sees the same internal types)
   - `extension ContainerScope { static let <case> = ... }` for each `@Scope` case
   - One extension per `@Container` with the typed API and SwiftUI plumbing
   - The bare `Inject.init()` overload (only when exactly one `@Container` binds to `.default`)

The plugin is **idempotent** and **incremental**: it re-runs only when the target's `.swift` files change, and the output is deterministic for the same input set.

## Anti-patterns and limits

- **Don't register the same type in two `@Module`s.** The plugin emits a build error: "@Module conflict: T is registered in multiple @Module enums."
- **Don't reference a module that doesn't exist.** The plugin emits a build error: "@Container(modules:) references unknown module `X`."
- **Don't reference an undeclared scope.** The plugin emits a build error pointing at the `@Container(scope: .X)` site and suggesting a `@Scope` enum case.
- **Don't put `@Container` in a target without the plugin enabled.** You'll get a storage-only class and unresolved-member errors downstream.
- **IDE seam**: after pulling new sources, run one build before the IDE catches up to the generated `App.resolve` overloads. Same experience as Hilt's annotation processor on Android.

## See also

- [`mvvm.md`](mvvm.md) — single-graph MVVM walkthrough using `@Container(modules:)`
- [`multi-container.md`](multi-container.md) — multi-graph patterns with `@Scope`
- [`design.md`](design.md) — macro contract and scope rules
