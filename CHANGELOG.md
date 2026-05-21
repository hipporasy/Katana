# Changelog

All notable changes to Katana are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/), and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

Nothing yet.

## [0.1.1]

A large additive release on top of `0.1.0`. Compile-time-safe containers, a build-plugin path for module composition, runtime cycle detection, and named bindings — all without changing any `0.1.0` call site. New surface is additive; existing `@Injectable` / `Container` / `Resolver` consumers continue to work unchanged.

### Added

#### Compile-time-safe containers

- **`@Container(T1.self, T2.self, ...)`** — attached macro that turns a class into a typed dependency graph. Emits a `Container`-backed storage, async `init(_:) async` with optional customize closure, one typed `resolve(_:)` overload per registered type, a nested `Snapshot: Resolver` struct, `snapshot() async -> Snapshot`, and a SwiftUI-gated nested `Inject` property wrapper. Resolving an unregistered type is now a **compile error**, not a runtime trap.
- **`@TestContainer(T1.self, ...)`** — test-target peer of `@Container`. Same shape plus post-construction `override(_:with:)` / `override(_:factory:)` methods and a `TestContainerMarker` conformance for project lint.
- **`Container.override(_:name:with:)` / `Container.override(_:name:factory:)`** — semantic alias for replacing an earlier registration. Clears any cached singleton so the new factory takes effect on the next resolve.
- **`Resolver` protocol** — promoted from a concrete struct so macro-generated `Snapshot` types can conform alongside the type-erased default.
- **`AnyResolver`** — the existing type-erased snapshot, kept as the runtime fallback. Returned by `Container.snapshot()`.

#### SwiftUI integration

- **`@Inject` property wrapper** — SwiftUI accessor reading `\.katanaResolver` from the environment. Type-erased path; typed `@App.Inject` per-graph variants are emitted by `@Container` / `@TestContainer`.
- **`.katana(_:)` view modifier** — installs an `any Resolver` in the SwiftUI environment under `\.katanaResolver`.

#### Module composition (Hilt-style)

- **`@Module(T1.self, T2.self, ...)`** — attached macro that groups injectable types into a named module. Emits a `static let types` array and a `KatanaModule` conformance for the annotated enum.
- **`@KatanaApp(modules: [...])`** — marker attribute consumed by the build plugin. Aggregates the listed modules into a typed dependency graph at build time, producing the same shape `@Container` emits inline.
- **`@KatanaTestApp(of: App.self)`** — test peer of `@KatanaApp`. Reads the production app's module list and emits an extension with typed `resolve(_:)` overloads plus post-construction `override(_:with:)`, `override(_:factory:)`, and `TestContainerMarker` conformance.
- **`KatanaCodegen` SwiftPM build-tool plugin** — scans the target's Swift sources, aggregates `@Module` type lists, and generates a typed extension per `@KatanaApp` / `@KatanaTestApp`. Opt-in per target via `plugins: ["KatanaCodegenPlugin"]` in `Package.swift`.
- **Per-app SwiftUI environment plumbing** — plugin generates `\.<app>Snapshot` env key, `.install<App>(_:)` view modifier, and a typed `@App.Inject` reading the per-app key. Multi-graph apps no longer need the manual env-key boilerplate from `multi-container.md`.
- **Cross-module conflict diagnostics** — `KatanaCodegen` validates the scanned graph before emission. Duplicate type registrations across `@Module`s, unknown module references, and unknown `@KatanaTestApp(of:)` targets all surface as build errors with `path:line:col` format.
- **`KatanaModule` protocol** — marker every `@Module`-annotated enum conforms to, with an associated `static var types: [any (Injectable & Sendable).Type]` requirement.

#### Runtime safety

- **Cycle detection** — `Container.resolutionChain` (public `@TaskLocal`) tracks the active resolution chain. Cycles trap with a readable `A → B → A` description plus remediation hints. Chain propagates through nested resolves, macro-generated `T.resolve(from:)`, and factory closures.
- **Named bindings** — every `register`, `resolve`, and `override` method gains an optional `name: String? = nil` parameter. Internal storage rekeyed from `ObjectIdentifier` to a composite `(ObjectIdentifier, String?)`. Multiple instances of the same `Type` can coexist with different names.

#### Example targets

- **`Example`** — full MVVM walk-through built around `@Container` and `@TestContainer`.
- **`ModularExample`** — companion executable showing the full `@Module` + `@KatanaApp` flow plus a `@KatanaTestApp` smoke test.

#### Test infrastructure

- **`KatanaCodegenCore`** library extracted from the executable, exposing `Scanner`, `Emitter`, and `Validator` as testable APIs.
- **`KatanaCodegenTests`** — 21 XCTest cases covering scanner parsing, validator diagnostics, and emitter output shape.
- **`ExampleTests`** — 19 Swift Testing cases exercising the example end-to-end including cycle detection and named bindings.
- **`KatanaTests`** — 25 macro-expansion tests covering `@Container`, `@TestContainer`, `@Module`, and `@Injectable`.

### Changed

- `Container.snapshot()` now returns `AnyResolver` (was the concrete `Resolver` struct). For most consumers this is source-compatible — the returned value still satisfies `Resolver` and supports `resolve(_:)`.
- `TestContainerMarker` no longer requires `Sendable` (was the original design, but adopting `Sendable` retroactively across files isn't allowed in Swift 6). Macro-generated test classes remain implicitly `Sendable` through their internals.

### Documentation

- **`Documentation/mvvm.md`** — full MVVM walkthrough updated for `@Container` / `@App.Inject` / `@TestContainer`.
- **`Documentation/multi-container.md`** — multi-graph patterns guide. Points at `modules.md` for the cleaner `@KatanaApp` path.
- **`Documentation/modules.md`** — user guide for the modular composition path (`@Module` + `@KatanaApp`).
- **`Documentation/roadmap.md`** — phased plan, all phases now marked shipped.
- `README.md` — Features list, SwiftUI integration section, modular composition section, examples, target list.

### Notes / limits

- Named bindings are container-level only — the `@Container` / `@KatanaApp` macro paths don't auto-handle them. Use them when you need multiple instances of the same type; reach for protocol abstractions for compile-time-safe disambiguation otherwise.
- `Container.snapshot()` includes **only unnamed singletons**. Named bindings remain accessible through `await container.resolve(_:name:)`.
- Cycle detection on the non-`Sendable` transient resolve path is **shallow only** — the `sending T` return type can't pass through a `withValue` closure under Swift 6's isolation analysis. Cycles entering a transient resolve are caught but the chain doesn't extend through them.

## [0.1.0] — Initial release

- `@Injectable` attached macro with `.singleton` / `.transient` scopes.
- `Container` actor.
- `Resolver` struct (synchronous snapshot of singletons).
- Swift 6 strict concurrency throughout; `NonisolatedNonsendingByDefault` upcoming feature enabled.
- macOS 13+, iOS 13+, tvOS 13+, watchOS 6+, macCatalyst 13+.

[Unreleased]: https://github.com/hipporasy/Katana/compare/0.1.1...HEAD
[0.1.1]: https://github.com/hipporasy/Katana/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/hipporasy/Katana/releases/tag/0.1.0
