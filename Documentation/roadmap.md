# Katana Roadmap — compile-time safe DI

This document captures the plan for moving Katana from runtime resolution (Swinject parity) to compile-time-checked dependency graphs, plus first-class testing ergonomics.

## North star

Two properties Katana should provide that Swinject does not:

1. **`resolve(T.self)` on an unregistered type is a compile error**, not a runtime trap.
2. **Substituting dependencies for tests requires zero ceremony** — overrides are first-class API, not a documented pattern.

## Constraints (worth re-stating because they shape every decision)

- Swift macros operate on a single declaration's syntax and can't see across files. Global dependency-graph analysis must happen at a single call site (the `@Container` declaration) that lists every type.
- Swift's type system can't express "`T` is one of the types in this parameter pack" — so the compile-time check is delivered through **overload resolution** (one `resolve(_:)` overload per registered type), not through where-clauses on a generic pack.
- Swift has no default generic parameters on types — defaults come from separate type names (overloaded property wrappers, in our case).
- `Container` stays an `actor`. Anything layered on top preserves that and stays `Sendable`.

## Vocabulary after all phases land

| Concept                                  | Name                  | Kind                                  |
|------------------------------------------|-----------------------|---------------------------------------|
| Per-type registration marker             | `@Injectable`         | attached macro (today)                |
| Runtime registry                         | `Container`           | actor (today)                         |
| Sync snapshot — type-erased              | `AnyResolver`         | struct                                |
| Sync snapshot — typed (per graph)        | `App.Snapshot`        | struct, macro-generated, nested       |
| Snapshot protocol                        | `Resolver`            | protocol                              |
| Typed dependency graph                   | `@Container`          | attached macro (NEW)                  |
| SwiftUI dep accessor — type-erased       | `@Inject`             | property wrapper (today, kept)        |
| SwiftUI dep accessor — typed             | `@App.Inject`         | property wrapper, macro-generated     |
| Environment install                      | `.katana(_:)`         | View modifier (today)                 |
| Override seam for tests                  | `Container.override(_:)` | method (NEW)                       |
| Typed test graph                         | `@TestContainer`      | attached macro (NEW)                  |
| Test container marker                    | `TestContainerMarker` | protocol (NEW)                        |

---

## Phase 1 — `Container.override(...)` (no new macro)

Smallest, zero-risk change. Adds semantic clarity for the override path used by tests.

```swift
extension Container {
    public func override<T: Injectable & Sendable>(_ type: T.Type, with instance: T) {
        register(type) { _ in instance }
    }

    public func override<T: Injectable & Sendable>(
        _ type: T.Type,
        factory: @escaping @Sendable (Container) async -> T
    ) {
        register(type, factory: factory)
    }
}
```

Mechanically identical to `register`; semantically marks "I'm replacing an earlier registration." Documented as the testing seam.

**Ship criteria**
- `ExampleTests` rewritten to use `.override(...)` for the swap cases.
- `mvvm.md` testing section references `override` instead of "register again."

---

## Phase 2a — Promote `Resolver` to a protocol

Pure refactor. Enables Phase 2b to generate typed snapshots without breaking `@Inject` / `.katana(_:)`.

```swift
public protocol Resolver: Sendable {
    func resolve<T: Sendable>(_ type: T.Type) -> T
}

public struct AnyResolver: Resolver {
    // current Resolver struct's implementation, renamed
}
```

`Container.snapshot()` returns `AnyResolver` (still concrete), `EnvironmentValues.katanaResolver` becomes `any Resolver`. `@Inject` reads through the protocol — no observable change for current users.

**Ship criteria**
- All existing tests pass unchanged.
- `Inject.swift` updated to read `@Environment(\.katanaResolver) private var resolver: any Resolver`.

---

## Phase 2b — `@Container` macro (the big one)

The single attached macro that delivers compile-time safety.

```swift
@Container(
    Logger.self,
    TodoRepository.self,
    TodoListViewModel.self
)
final class App {
    override func configure(_ container: Container) async {
        // production-only customisation (optional)
        await container.override(Logger.self) { _ in ProductionLogger() }
    }
}
```

Macro emits, on the annotated class:

1. **`init(_ customize: ...)`** — async bootstrap. Builds the inner `Container`, registers each type from the macro arg list in order, calls `configure(_:)` (subclass hook), then `customize?(_:)` (closure hook used by tests).
2. **`resolve(_:)` overloads** — one per registered type. Async, type-checked. Calling `resolve(_: Foo.Type)` when `Foo` isn't in the list is "no matching overload" — a real compile error.
3. **Nested `struct Snapshot: Resolver`** — typed sync resolver with stored properties for each registered type, typed `resolve(_:)` overloads, and a type-erased fallback to satisfy `Resolver`.
4. **`snapshot() async -> Snapshot`** — returns the typed concrete (not `any Resolver`).
5. **Nested `struct Inject: DynamicProperty`** — typed `@App.Inject` property wrapper that reads the environment-installed `App.Snapshot` and calls its typed overloads.

Conceptually generated:

```swift
extension App {
    init(_ customize: (@Sendable (Container) async -> Void)? = nil) async { ... }

    func resolve(_: Logger.Type) async -> Logger { ... }
    func resolve(_: TodoRepository.Type) async -> TodoRepository { ... }
    func resolve(_: TodoListViewModel.Type) async -> TodoListViewModel { ... }

    func snapshot() async -> Snapshot { ... }

    struct Snapshot: Resolver {
        let logger: Logger
        let todoRepository: TodoRepository
        let todoListViewModel: TodoListViewModel

        func resolve(_: Logger.Type) -> Logger { logger }
        func resolve(_: TodoRepository.Type) -> TodoRepository { todoRepository }
        func resolve(_: TodoListViewModel.Type) -> TodoListViewModel { todoListViewModel }
        func resolve<T: Sendable>(_ type: T.Type) -> T { /* type-erased fallback */ }
    }

    @propertyWrapper
    struct Inject<Value: Sendable>: DynamicProperty {
        @Environment(\.appSnapshot) private var snapshot
        var wrappedValue: Value { snapshot!.resolve(Value.self) }
    }
}

extension EnvironmentValues {
    var appSnapshot: App.Snapshot? { ... }
}
```

> Note: `App.Inject<Value>` has only one generic; `Value` is inferred from the property declaration as it is for `@State`. The Swift inference path here is unsurprising — no exotic generics tricks needed.

### Default vs typed `@Inject` — when to use which

Swift has no real "default generic parameter" mechanism, so the default behaviour is delivered by a **different wrapper** — same `@` prefix, no qualifier:

| Form                              | Where it reads from              | Compile-time check? | When to use                                  |
|-----------------------------------|----------------------------------|---------------------|----------------------------------------------|
| `@Inject var x: T`                | `\.katanaResolver` (`any Resolver`) | No (runtime trap)   | Single-container apps; quick prototypes      |
| `@App.Inject var x: T`            | `\.appSnapshot` (`App.Snapshot`) | **Yes**             | Anything where you want safety               |
| `@Feature.Inject var x: T`        | `\.featureSnapshot`              | **Yes**             | Multi-container apps (see "Multiple containers" below) |

A typical app pattern: install **one** snapshot at the root with `.katana(snap)` and use bare `@Inject` everywhere — the typed wrappers only earn their cost when you have more than one graph in flight, or when a refactor-safety pass demands the compile-time guarantee.

### Compile-time error story

```swift
let app = await App()
let vm = await app.resolve(TodoListViewModel.self)   // OK
let bad = await app.resolve(Foo.self)                // ❌ no matching overload

let snap = await app.snapshot()
let logger = snap.resolve(Logger.self)               // OK
let alsoBad = snap.resolve(Foo.self)                 // ❌ no matching overload

struct V: View {
    @App.Inject var vm: TodoListViewModel             // OK
    @App.Inject var nope: Foo                         // ❌ App.Snapshot has no resolve(Foo.Type)
}
```

The runtime escape hatch (`AnyResolver.resolve<T>`) still exists for the bare `@Inject` and for anyone who needs dynamic resolution. The trap message there should explicitly suggest `@App.Inject` for compile-time checking.

**Open design decision (decide before coding)**

The `Snapshot` stored-property names need a convention. Two choices:

| Convention | Example | Trade-off |
|---|---|---|
| Lowercased type name | `todoListViewModel: TodoListViewModel` | Reads naturally; rare collisions |
| Object-identifier dictionary + computed properties | `_storage: [...]` + `var todoListViewModel: TodoListViewModel { ... }` | Avoids any name shape collisions; slightly more generated code |

**Recommendation:** lowercased type name. It's what a human would write.

**Ship criteria**
- `App` in the `Example` target rewritten to use `@Container`.
- Deleting a registration from the macro arg list causes a readable compile error at every `resolve` / `@App.Inject` site.
- `ExampleTests` uses the closure init on `@Container` for test overrides.
- All existing tests pass.

---

## Phase 2c — `@TestContainer` macro (first-class testing primitive)

Tests deserve their own named concept, not a documented pattern. `@TestContainer` is the test-target peer of `@Container`. Same compile-time safety, override-first ergonomics, semantic distinction.

```swift
@TestContainer(
    Logger.self,
    TodoRepository.self,
    TodoListViewModel.self
)
final class TestApp {
    // Default overrides used by every test that doesn't replace them.
    override func configure(_ c: Container) async {
        await c.override(Logger.self, with: SilentLogger())
    }
}
```

### What the macro emits

Largely identical to `@Container`, with three test-shaped additions:

```swift
extension TestApp {
    // Same as @Container:
    init(_ customize: (@Sendable (Container) async -> Void)? = nil) async { ... }
    func resolve(_: Logger.Type) async -> Logger { ... }
    func resolve(_: TodoRepository.Type) async -> TodoRepository { ... }
    func resolve(_: TodoListViewModel.Type) async -> TodoListViewModel { ... }
    func snapshot() async -> Snapshot { ... }
    struct Snapshot: Resolver { ... }
    @propertyWrapper struct Inject<Value: Sendable>: DynamicProperty { ... }

    // Test-specific additions:

    /// Synchronously override after construction. Convenient when a test wants
    /// to swap one dep without re-building the whole graph.
    func override<T: Injectable & Sendable>(_ type: T.Type, with instance: T) async

    /// Record every type resolved through this container. Tests can assert
    /// "the view model touched the network" without injecting a counting spy.
    var resolutionLog: [ObjectIdentifier] { get async }

    /// Marker conformance — lets linters / build scripts find every test
    /// container in the codebase.
    /* generated: extension TestApp: TestContainerMarker {} */
}
```

### How tests read

Three different shapes, each ergonomic:

```swift
// 1. Closure init — overrides at construction time
@Test func togglesCompletion() async {
    let app = await TestApp { c in
        await c.override(TodoRepository.self) { container in
            let logger = await container.resolve(Logger.self)
            let repo = TodoRepository(logger: logger)
            await repo.add(title: "Seed")
            return repo
        }
    }
    let vm = await app.resolve(TodoListViewModel.self)
    // ... assertions ...
}

// 2. Post-construction override — swap one thing
@Test func usesSpyLogger() async {
    let app = await TestApp()
    let spy = SpyLogger()
    await app.override(Logger.self, with: spy)
    let vm = await app.resolve(TodoListViewModel.self)
    await vm.add(title: "x")
    #expect(spy.captured.contains { $0.contains("x") })
}

// 3. Resolution log — assert which deps were touched
@Test func loadDoesNotHitNetwork() async {
    let app = await TestApp()
    let vm = await app.resolve(TodoListViewModel.self)
    await vm.load()
    let log = await app.resolutionLog
    #expect(!log.contains(ObjectIdentifier(Network.self)))
}
```

### Why a separate macro, not just `@Container` in a test target

It's tempting to say "tests just use `@Container` with a different name." That works, but you lose:

1. **Discoverability.** Autocomplete on `@Test` shows `@TestContainer` next to it. New contributors find the test pattern without reading docs.
2. **Marker conformance.** `protocol TestContainerMarker {}` lets the project's lint script enforce "no `@TestContainer` outside `Tests/`" — production code can't accidentally take a test-only dependency.
3. **Test-only API surface.** Resolution logging and post-construction `override` are noise in production but valuable in tests. Keeping them on `@TestContainer` only is honest.
4. **Future room.** Once we have a marker conformance, Phase 4 work like auto-generated mock-by-default behaviour, snapshot-vs-spy mode switches, or XCTest/Swift Testing integration hooks all have a place to land that doesn't pollute `@Container`.

### The honest cost: duplicated type list

`@TestContainer(Logger.self, TodoRepository.self, TodoListViewModel.self)` repeats what `@Container` already says, because Swift macros can't read another declaration's annotation arguments across files. Three ways to live with this:

1. **Accept it (recommended).** A copy-pasted three-to-fifteen-line list of `.self`s is a small price for compile-time safety in both production and tests. Diff review catches drift.
2. **Lint check.** Project-level script that parses both `@Container` and `@TestContainer` arg lists and fails CI on mismatch. Easy regex; 20 lines of Python.
3. **Future: `@KatanaModule`.** Extract the type list to a module enum that both macros consume. Doesn't fully avoid the issue (the module's `static let types` is still a runtime array, not a syntax-level type list the macro can iterate) but it does centralise. Considered in Phase 4.

For v1, we ship with (1) and document the lint pattern (2) for any project that wants it.

### Ship criteria

- `@TestContainer` macro emits the seven declarations listed above.
- `Sources/Katana/TestContainerMarker.swift` defines the marker protocol.
- `Tests/ExampleTests/` adds a `TestApp` class and rewrites every test to use it.
- `Documentation/mvvm.md` testing section uses `@TestContainer`.
- The macro-generated overloads error at compile time when the test code resolves a type that isn't in the `@TestContainer` arg list — symmetric with `@Container`.

---

---

## Multiple containers — the guide

Moved to [`multi-container.md`](multi-container.md). The roadmap keeps only the planning items.

---

## Phase 3 — Optional polish

These land only if real usage demands them.

### 3a. `@Container(modules: [DataModule.self, UIModule.self])`

For apps whose registration list grows past ~15 types. Modules are `enum`s with a static `types` property; the macro reads the lists and merges. No new safety properties, just organisation.

### 3b. Runtime cycle detection

Track an active-resolution stack inside `Container`; on re-entry for the same type, trap with a readable cycle description. Compile-time cycle detection is gated on cross-file macro analysis and stays out of scope.

### 3c. Named bindings / qualifiers

For "I want two `Logger`s, one console and one file." Add `@Injectable(name: "console")` + `container.resolve(Logger.self, name: "console")`. Wait for a real use case before adding API surface.

---

## What this changes in the existing surface

| File                              | Change                                                                       |
|-----------------------------------|------------------------------------------------------------------------------|
| `Sources/Katana/Container.swift`  | Add `override(_:with:)` / `override(_:factory:)`; `snapshot()` returns `AnyResolver` |
| `Sources/Katana/Resolver.swift`   | Becomes `protocol Resolver` + `struct AnyResolver`                            |
| `Sources/Katana/Inject.swift`     | Reads `any Resolver` from environment                                         |
| `Sources/KatanaMacros/`           | New `@Container` extension macro; new `@TestContainer` extension macro        |
| `Sources/Katana/Katana.swift`     | Declare the new macros                                                        |
| `Sources/Katana/TestContainerMarker.swift` | NEW — marker protocol generated test containers conform to                |
| `Sources/Example/Composition.swift` | Replaced by `final class App` annotated with `@Container`                   |
| `Tests/ExampleTests/`             | Test overrides switch to closure-on-`@Container`                              |
| `Documentation/mvvm.md`           | Update view + composition-root snippets to use `App` + `@App.Inject`         |
| `Documentation/multi-container.md` | NEW — extracted from this roadmap once Phase 2b lands                       |
| `README.md`                       | Feature list adds compile-time checking + typed `@Inject`                     |

---

## Execution order

1. **Phase 1** — `Container.override(...)`. Locks override semantics. ~30 LOC, zero risk.
2. **Phase 2a** — `Resolver` → protocol + `AnyResolver`. Pure refactor, all tests green.
3. **Phase 2b** — `@Container` macro. The high-risk piece; build a throwaway prototype first to confirm the SwiftSyntax expansion of `init` + `resolve` overloads + nested `Snapshot` + nested `Inject` + `EnvironmentValues` extension all read cleanly.
4. **Phase 2c** — `@TestContainer` macro. Reuses ~80% of the Phase 2b SwiftSyntax code with the test-shaped additions on top. Rewrite `ExampleTests` to use it.
5. **Docs sweep** — update `mvvm.md` and `README.md` to match. Promote the multi-container section into `Documentation/multi-container.md`.
6. **Phase 3+** items — only on demand.

Cut points:

- Phase 1 alone — shippable as a patch release.
- Phase 1 + 2a — shippable; `Resolver` becomes extensible.
- Phase 1 + 2a + 2b — shippable; compile-time safe production.
- **Phase 1 + 2a + 2b + 2c** — the target for the next minor release (0.2.0). Compile-time safe production AND tests, no documented pattern as a substitute for a primitive.
