# `@Module` — module composition

Katana ships two ways to declare a dependency graph:

- **`@Container(T1.self, T2.self, ...)`** — inline type list, pure macro, no build plugin. Best for small apps and single-file composition. Covered in [`mvvm.md`](mvvm.md).
- **`@Module` + `@KatanaApp` + `KatanaCodegen` build plugin** — type lists split across files, aggregated at build time. Best for larger apps with feature-team-owned modules. This document.

Both paths produce **structurally identical** code: typed `resolve(_:)` overloads, typed `Snapshot`, typed `Inject`. Compile-time safety is the same. Pick the shape that fits the codebase.

## Quick tour

```swift
// Modules/ServiceModule.swift
@Module(Logger.self, AnalyticsClient.self)
enum ServiceModule {}

// Modules/RepositoryModule.swift
@Module(TodoRepository.self, UserRepository.self)
enum RepositoryModule {}

// App.swift
@KatanaApp(modules: [ServiceModule.self, RepositoryModule.self])
final class App {}
```

The `KatanaCodegen` build plugin scans the target, aggregates the type lists across files, and emits a typed extension on `App` with:

- `init(_:) async` taking an optional override closure
- `resolve(_:) async` overload per registered type
- `App.Snapshot` (typed, `Sendable`)
- `snapshot() async -> Snapshot`
- `App.Inject` property wrapper for SwiftUI
- `EnvironmentValues.appSnapshot` typed env key
- `View.installApp(_:)` convenience modifier

After build:

```swift
let app = await App()
let repo = await app.resolve(TodoRepository.self)    // ✅ compile-checked
let bad = await app.resolve(URLSession.self)         // ❌ compile error
let snap = await app.snapshot()                       // App.Snapshot
```

## Enabling the plugin in your `Package.swift`

The plugin is opt-in per target:

```swift
.executableTarget(
    name: "MyApp",
    dependencies: ["Katana"],
    plugins: ["KatanaCodegenPlugin"]   // ← here
)
```

If your `MyApp` target uses `@KatanaApp` and you haven't added the plugin, the macro produces an empty class — every call site that expects `resolve(_:)`, `snapshot()`, etc. will fail to compile, surfacing the missing plugin.

## SwiftUI integration

The plugin generates a typed env key per app, so multi-graph apps work without any manual env-key boilerplate (the manual workaround in [`multi-container.md`](multi-container.md) is for plain `@Container` only).

```swift
@main
struct MyApp: SwiftUI.App {
    @State private var snapshot: App.Snapshot?

    var body: some Scene {
        WindowGroup {
            if let snapshot {
                ContentView().installApp(snapshot)        // ← generated modifier
            } else {
                ProgressView().task { snapshot = await App().snapshot() }
            }
        }
    }
}

struct ContentView: View {
    @App.Inject var repo: TodoRepository                  // ← compile-checked
    var body: some View { /* ... */ }
}
```

For multiple graphs in the same app, each one gets its own typed env key, modifier, and `Inject`:

```swift
@KatanaApp(modules: [...])
final class App {}

@KatanaApp(modules: [...])
final class Checkout {}

// Plugin generates:
//   - \.appSnapshot, .installApp(_:), @App.Inject
//   - \.checkoutSnapshot, .installCheckout(_:), @Checkout.Inject
//
// They're independent — view `@App.Inject var x: T` only sees App's graph;
// `@Checkout.Inject var y: U` only sees Checkout's.
```

## Testing — `@KatanaTestApp`

The test peer reads the production app's module list and emits the same shape plus `override(_:with:) async`, `override(_:factory:) async`, and `TestContainerMarker` conformance:

```swift
@KatanaTestApp(of: App.self)
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

`@KatanaTestApp` requires the plugin (it reads the production `@KatanaApp`'s module list). In your test target's `Package.swift`:

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: ["MyApp", "Katana"],
    plugins: ["KatanaCodegenPlugin"]
)
```

## How the plugin works

`KatanaCodegen` is a SwiftPM build-tool plugin that runs once per target before compilation. It:

1. Parses every `.swift` file in the target with SwiftSyntax (read-only — no source modification).
2. Collects `@Module(...)` declarations, recording each module's name and type list.
3. Collects `@KatanaApp(modules: [...])` and `@KatanaTestApp(of: …)` declarations.
4. Aggregates types per app (deduplicating across modules).
5. Emits a single `KatanaGenerated.swift` file in the build directory containing:
   - One extension per `@KatanaApp` with the typed API
   - One extension per `@KatanaTestApp` with the test API + marker conformance
   - Per-app `EnvironmentKey`, `EnvironmentValues` extension, and `View` modifier
6. The build system compiles the generated file alongside the user's sources.

The plugin is **idempotent** and **incremental**: it re-runs only when the target's `.swift` files change, and the output is deterministic for the same input set.

## When to choose `@Container` vs `@KatanaApp`

| Use `@Container` (inline) | Use `@KatanaApp` (modular) |
|---|---|
| Single file is enough          | Type list spans multiple files / teams       |
| You want no build dependency  | You're OK with a SwiftPM plugin              |
| Small app, < ~15 dependencies | Larger app, modular ownership                |
| Faster cold builds             | Slower cold builds (plugin scans + codegen)  |
| Single graph                   | Multi-graph (per-feature, plugin SDKs, etc.) |

Mix freely — a project can use both on different targets.

## Anti-patterns and limits

- **Don't register the same type in two `@Module`s.** The plugin deduplicates silently today; a future version may diagnose the conflict.
- **Don't reference a module that doesn't exist.** The plugin emits a Swift `#error` directive when `@KatanaTestApp(of: X.self)` can't find `X`'s `@KatanaApp`.
- **Don't put `@KatanaApp` in a target without the plugin enabled.** You'll get an empty class and unresolved-member errors downstream.
- **IDE seam**: after pulling new sources, run one build before the IDE catches up to the generated `App.resolve` overloads. Same experience as Hilt's annotation processor on Android.

## See also

- [`mvvm.md`](mvvm.md) — single-graph MVVM walkthrough using `@Container`
- [`multi-container.md`](multi-container.md) — multi-graph patterns with plain `@Container` (manual env-key boilerplate)
- [`design.md`](design.md) — macro contract and scope rules
- [`roadmap.md`](roadmap.md) — phased plan
