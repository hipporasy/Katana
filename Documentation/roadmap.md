# Katana Roadmap — compile-time safe DI

This document captures the plan for moving Katana from runtime resolution (Swinject parity) to compile-time-checked dependency graphs, plus first-class testing ergonomics.

## North star

Two properties Katana provides that Swinject does not:

1. **`resolve(T.self)` on an unregistered type is a compile error**, not a runtime trap.
2. **Substituting dependencies for tests requires zero ceremony** — overrides are first-class API, not a documented pattern.

## Constraints (worth re-stating because they shape every decision)

- Swift macros operate on a single declaration's syntax and can't see across files. Cross-file aggregation (modules, scope validation) happens in a **SwiftPM build-tool plugin** (`KatanaCodegen`), not in macros.
- Swift's type system can't express "`T` is one of the types in this parameter pack" — so the compile-time check is delivered through **overload resolution** (one `resolve(_:)` overload per registered type), not through where-clauses on a generic pack.
- Swift has no default generic parameters on types — `@Inject`'s bare form is enabled by a **plugin-emitted `init()` overload** that points at the `.default`-scoped container's env slot.
- `Container` stays an `actor`. Anything layered on top preserves that and stays `Sendable`.

## Current vocabulary (as of 0.2.0)

| Concept                                  | Name                    | Kind                                                |
|------------------------------------------|-------------------------|-----------------------------------------------------|
| Per-type registration marker             | `@Injectable`           | attached macro                                      |
| Runtime registry                         | `Container`             | actor                                               |
| Sync snapshot — type-erased              | `AnyResolver`           | struct                                              |
| Sync snapshot — typed (per graph)        | `<Graph>.Snapshot`      | struct, plugin-generated, nested                    |
| Snapshot protocol                        | `Resolver`              | protocol                                            |
| Module grouping                          | `@Module`               | attached macro                                      |
| Container scope identity                 | `ContainerScope`        | struct (`.default` built in; custom via `@Scope`)   |
| Scope registry                           | `@Scope`                | attached macro on enum                              |
| Typed dependency graph                   | `@Container`            | attached macro (modules-only)                       |
| SwiftUI dep accessor                     | `@Inject` / `@Inject(\.X)` | framework-level property wrapper                 |
| Environment install                      | `View.katana(_:)`       | View modifier, plugin-generated per snapshot type   |
| Override seam for tests                  | `Container.override(_:)` | method                                             |
| Typed test graph                         | `@TestContainer`        | attached macro (modules-only)                       |
| Test container marker                    | `TestContainerMarker`   | protocol                                            |
| Build-time codegen                       | `KatanaCodegenPlugin`   | SwiftPM build-tool plugin                           |

---

## Phase history

### Phase 1 — `Container.override(...)` (shipped 0.1.0)

Adds semantic clarity for the override path used by tests. `register` aliased as `override(_:with:)` / `override(_:factory:)` to mark "I'm replacing an earlier registration."

### Phase 2a — `Resolver` protocol + `AnyResolver` (shipped 0.1.0)

Pure refactor that enabled Phase 2b to generate typed snapshots without breaking the framework-level `@Inject`.

### Phase 2b — `@Container` macro (shipped 0.1.0, reworked in 0.2.0)

The original `@Container(T1.self, T2.self, ...)` form took an inline variadic type list and emitted everything in-process (member macro only — no build plugin needed). 0.2.0 collapsed this with the original `@KatanaApp` form into one modules-only macro driven by the build plugin.

### Phase 2c — `@TestContainer` macro (shipped 0.1.0, reworked in 0.2.0)

Test-target peer of `@Container`. Same shape plus post-construction `override(_:with:) async` / `override(_:factory:) async` and `TestContainerMarker` conformance. Now modules-only like its production peer.

### Phase 3 — `@Module` + `KatanaCodegenPlugin` (shipped 0.1.1, expanded in 0.2.0)

Originally a parallel composition shape (`@KatanaApp(modules: [...])` + plugin) for splitting graphs across files. 0.2.0 made the plugin path the **only** path — `@Container(modules: [...])` requires it. The plugin gained scope validation, per-scope env keys, and bare `@Inject` init emission.

### Phase 4 — `@Scope` + multi-graph ergonomics (shipped 0.2.0)

Declared custom `ContainerScope` cases enable multi-graph apps without manual env-key plumbing. The `@Inject(\.<scope>)` form replaces the previous nested `@<Graph>.Inject` wrappers; bare `@Inject` works for the single `.default`-scoped container.

### Phase 5 — Runtime safety nets (shipped 0.1.1, ongoing)

- **Cycle detection** via `Container.resolutionChain` (`@TaskLocal`). Cycles trap with `A → B → A` remediation. Non-`Sendable` transient path is shallow.
- **Named bindings** — `register(_:name:)` / `resolve(_:name:)` / `override(_:name:_:)`. Container-level escape hatch; macro paths don't auto-handle names.

---

## What 0.2.0 changed in the existing surface

| File                                         | Change                                                                       |
|----------------------------------------------|------------------------------------------------------------------------------|
| `Sources/Katana/ContainerScope.swift`        | NEW — `ContainerScope` struct + `KatanaScope` marker protocol                |
| `Sources/Katana/Inject.swift`                | Rewritten — keypath-based `Inject(_ keyPath:)`; bare init plugin-emitted     |
| `Sources/Katana/Katana.swift`                | `@Container` / `@TestContainer` reworked to `(scope:, modules:)`; `@Scope` added; `@KatanaApp` / `@KatanaTestApp` removed |
| `Sources/KatanaMacros/ContainerMacro.swift`  | Modules-only marker macro; emits storage stub + designated init              |
| `Sources/KatanaMacros/ScopeMacro.swift`      | NEW — emits `KatanaScope` conformance; plugin handles the heavy lifting       |
| `Sources/KatanaMacros/KatanaAppMacro.swift`  | DELETED                                                                       |
| `Sources/KatanaMacros/KatanaTestAppMacro.swift` | DELETED                                                                    |
| `Sources/KatanaCodegenCore/Scanner.swift`    | Reads `@Container` / `@TestContainer` / `@Scope`; collects user imports      |
| `Sources/KatanaCodegenCore/Validator.swift`  | NEW checks: unknown scope, duplicate scope bindings                          |
| `Sources/KatanaCodegenCore/Emitter.swift`    | Per-scope env keys, install modifier overloads, bare `Inject.init()` emission, `ContainerScope` static emission, user-import replay |
| `Sources/Example/`                           | Inline `@Container(...)` replaced with `@Module` enums + `@Container(modules:)` |
| `Sources/ModularExample/`                    | `@KatanaApp` / `@KatanaTestApp` → `@Container` / `@TestContainer`            |
| `Tests/ExampleTests/`                        | Switched to modules-only test container at custom `.test` scope              |
| `Documentation/*`                            | Rewritten — see file list                                                    |

---

## Releasing

For each release:

1. **Verify suite green** — `swift build && swift test`. Run both example executables: `swift run Example` and `swift run ModularExample`.
2. **Bump CHANGELOG** — promote the `[Unreleased]` section to the new version with today's date; add fresh empty `[Unreleased]` at the top.
3. **Tag** — `git tag <version>` (e.g. `git tag 0.3.0`). Do NOT update the `from: "..."` constraint in `README.md`'s install snippet until consumers can actually resolve the tag — bump it on the same commit as the tag is fine.
4. **Push** — `git push --follow-tags`.
5. **GitHub release** — create the release on GitHub with the CHANGELOG entry pasted as the release body.

CHANGELOG conventions: [Keep a Changelog](https://keepachangelog.com/) format, [SemVer](https://semver.org/). Minor versions for feature additions, patch for bug fixes only.

The 0.2.0 release is a **breaking change** (removed `@KatanaApp` / `@KatanaTestApp`; the inline-arg form of `@Container` gone; plugin is now mandatory). Document migration in `CHANGELOG.md`.
