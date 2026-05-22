# Katana Design Rules

## Core Concept

Katana is a Swift macro-based DI framework. Macros mark intent; the **`KatanaCodegen` build plugin** does the cross-file aggregation and code generation; the runtime is minimal. Think Dagger/Hilt semantics, Swift idioms.

Two layers of compile-time safety:

- **Type-level**, supplied by `@Injectable` — every dependency is type-resolved at compile time. Mistyped or missing init labels fail to build.
- **Graph-level**, supplied by `@Container(modules: [...])` — typed `resolve(_:)` overloads per registered type, plus per-scope `EnvironmentValues` slots typed on the snapshot. Resolving an unregistered type or referencing an undeclared scope is a compile error, not a runtime trap.

## The Pieces

### Runtime primitives

- **`Container`** — an `actor`. The runtime registry. All `register` / `resolve` / `override` is `async`. Non-negotiable; see `swift6.md`.
- **`Injectable`** — the protocol every resolvable type conforms to:
  ```swift
  public protocol Injectable {
      static var scope: Scope { get }                    // default .singleton
      static func resolve(from container: Container) async -> sending Self
  }
  ```
- **`Resolver`** — a protocol any synchronous snapshot conforms to. Generic erased fallback (`AnyResolver`) plus codegen-emitted typed `Snapshot` structs:
  ```swift
  public protocol Resolver: Sendable {
      func resolve<T: Sendable>(_ type: T.Type) -> T
  }
  ```
- **`Scope`** (the injectable scope, distinct from container scope) — `.singleton` (cached, `Sendable` required) or `.transient` (`sending`-transferred, non-`Sendable` OK).
- **`ContainerScope`** — identifies a dependency graph. `.default` is built in; custom scopes are declared with `@Scope` and codegen-emitted as `static let` properties on `ContainerScope`.

### Macros

- **`@Injectable`** — per-type, attached extension macro. Synthesises `Injectable` conformance + `resolve(from:)`. Compile-time only, no plugin needed.
- **`@Module(T1.self, ...)`** — groups injectable types into a case-less enum. Emits `static let types` + `KatanaModule` conformance.
- **`@Scope`** — declares an enum whose cases become `ContainerScope` statics. The macro only emits the `KatanaScope` marker conformance; the plugin emits the actual `static let` properties at codegen time.
- **`@Container(scope:, modules:)`** — per-graph, attached member macro. The macro emits only `__katanaContainer` storage + a designated init seam. The plugin emits the typed `init(_:)`, `resolve(_:)` overloads, nested `Snapshot`, `snapshot() async`, the per-scope `EnvironmentValues` slot, and the `View.katana(_:)` install modifier.
- **`@TestContainer(scope:, modules:)`** — test-target peer. Same shape plus post-construction `override(_:with:) async` / `override(_:factory:) async` and `TestContainerMarker` conformance for project lint.

### Build plugin

- **`KatanaCodegenPlugin`** — SwiftPM build-tool plugin. Scans the target's `.swift` sources for `@Module` / `@Container` / `@TestContainer` / `@Scope`, validates the graph (duplicate registrations, unknown module references, unknown scope references, duplicate scope bindings), and emits a `KatanaGenerated.swift` file with the typed extensions, env keys, install modifiers, and the bare `Inject.init()` overload for the `.default` scope.

The plugin is **mandatory** on every target that uses `@Container`. Without it, only the macro's storage stub exists and every consumer site fails to compile.

## Scopes (container scope vs injectable scope — they're distinct)

- **`Scope`** (`.singleton` / `.transient`) is per-`@Injectable` type and controls caching.
- **`ContainerScope`** (`.default` + custom cases via `@Scope`) is per-`@Container` graph and controls which `EnvironmentValues` slot SwiftUI views read through `@Inject(\.<scope>)`.

### Injectable scope

#### Singleton (default)

The container caches the instance and returns the same reference on every resolve. The type **must be `Sendable`**.

```swift
@Injectable                      // singleton by default
@Injectable(scope: .singleton)   // explicit

final class NetworkService: Sendable { ... }
@Observable final class AppState { ... }      // @Observable is implicitly Sendable
@MainActor final class ViewModel { ... }      // @MainActor is implicitly Sendable
actor TodoRepository { ... }                  // actors are implicitly Sendable
```

#### Transient

A new instance is created on every resolve. The container creates the value and **transfers ownership** to the caller via `sending` (SE-0430). The type does **not** need to be `Sendable`.

```swift
@Injectable(scope: .transient)
final class RequestContext { ... }  // non-Sendable is fine
```

#### Resolution signatures

```swift
// Singleton — T must be Sendable
func resolve<T: Injectable & Sendable>(_ type: T.Type, name: String? = nil) async -> T

// Transient — ownership transferred, non-Sendable OK
func resolve<T: Injectable>(_ type: T.Type, name: String? = nil) async -> sending T
```

The macro generates `resolve(from:)` using the same split — singleton conformance constrains `Self: Sendable`, transient uses `sending Self`.

### Container scope

Each `@Container` binds to exactly one `ContainerScope`. The plugin uses this to:

1. Pick the `EnvironmentValues` slot name (`.default` → `\.katanaDefault`, other scopes → `\.<caseName>`).
2. Validate that no two containers share a scope (per target).
3. Emit the bare `Inject.init()` overload only for the single `.default`-bound container — when no container binds to `.default`, bare `@Inject` is a compile error.

```swift
@Scope
enum AppScope {
    case checkout
    case payment
}

@Container(modules: [ServiceModule.self, RepositoryModule.self])
final class App {}                                          // implicit .default

@Container(scope: .checkout, modules: [CheckoutModule.self])
final class CheckoutGraph {}

@Container(scope: .payment, modules: [PaymentModule.self])
final class PaymentGraph {}
```

SwiftUI views read with key paths matching the scope name:

```swift
@Inject var session: AuthSession                            // .default
@Inject(\.checkout) var vm: CheckoutViewModel               // .checkout
@Inject(\.payment) var processor: PaymentClient             // .payment
```

## `@Observable` Support

`@Observable` classes (iOS 17+) work as injectables without any special handling — they're reference types and singletons, exactly what the container stores. Mark them `@Injectable` like anything else:

```swift
@Observable
@Injectable
final class AppState {
    init(preferences: UserPreferences) { ... }
}
```

The container holds the single `@Observable` instance; SwiftUI observation works because the same reference is vended everywhere.

`ObservableObject` types work identically — no distinction at the container level.

## What Macros and Codegen Must NOT Do

- **Do not generate `@MainActor` isolation on the `resolve` method** — callers own their isolation context. `nonisolated async` is the canonical signature.
- **`@Injectable` does not access stored properties of the type being expanded** — only init parameter types and labels. (`@Container` and `@TestContainer` macros don't read user properties either; the plugin reads only attribute syntax.)
- **`@Injectable` does not support multiple `init` overloads automatically** — if a type has multiple inits, the macro picks the first designated initializer and emits a warning. Mark the rest `convenience` to silence.
- **Macros must not modify the user's existing declarations** — they may ADD members or extensions, but never alter what the user wrote.
- **The codegen plugin replays user imports** (via the scanner's `ImportDecl`) so generated files can reference the same internal types user files do — important for test targets using `@testable import`.

## Runtime safety

### Cycle detection

`Container.resolve` traps with a readable `A → B → A` chain when a cyclic dependency is detected during resolution. The active chain lives in `Container.resolutionChain`, a public `@TaskLocal` that propagates through nested resolves, macro-generated `T.resolve(from:)`, and factory closures.

Limit: the non-`Sendable` transient resolve path does a shallow check only (the `sending T` return type can't pass through a `withValue` closure under Swift 6's isolation analysis).

Compile-time cycle detection would require cross-file macro analysis; for now we rely on the runtime trap.

### Named bindings

`register(_:name:)` / `resolve(_:name:)` / `override(_:name:_:)` accept an optional name. Multiple instances of the same `Type` coexist under different names. The macro path doesn't auto-handle names — they're a container-level escape hatch. For compile-time-safe disambiguation, prefer protocol abstractions or separate `@Scope`s.

## Error Cases

If `@Injectable` is applied to a type with no `init` parameters, it generates a trivial conformance:

```swift
extension LoggerService: Injectable {
    static func resolve(from container: Container) async -> sending Self { Self() }
}
```

If `@Injectable` is applied to a type that can't be initialized (protocol, enum, extension), the macro emits a compile-time diagnostic.

If `@Container` or `@TestContainer` is applied to anything other than a class, the macro emits a compile-time diagnostic. `@Module` and `@Scope` require an enum. `@Scope` rejects cases with associated values.

If `@Container` references an unknown `@Module` or an undeclared `@Scope` case, the plugin emits a `#error` at codegen time pointing at the call site.

If two `@Container`s share a scope in the same target, the plugin emits a `#error` naming both classes.
