# Katana

A Swift 6 macro-based dependency injection framework. Dagger/Hilt semantics, Swift idioms, minimal runtime.

**[API Documentation →](https://hipporasy.github.io/Katana/)**

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

- **One macro, no codegen step** — `@Injectable` is a compiler plugin built on SwiftSyntax.
- **Actor-based container** — `Container` is an `actor`; thread safety is enforced by Swift's type system, no `@unchecked Sendable`.
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

Build a container, register types, resolve:

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

## Development

```bash
swift build                                    # Build all targets
swift test                                     # 17 macro expansion tests
swift run KatanaClient                         # Runtime smoke test
swift test --filter KatanaTests/testEmptyInit  # Single test
```

The package has three SPM targets:

- `KatanaMacros` — the compiler plugin (runs at build time)
- `Katana` — the public library users import
- `KatanaClient` — runtime demo / smoke test

Tests live in `KatanaTests` and use `assertMacroExpansion` to verify the *text* the macro produces, not runtime behavior.

## Design

See [`Docs/design.md`](Docs/design.md) for the architectural rationale and [`Docs/swift6.md`](Docs/swift6.md) for the Swift 6 concurrency rules the library is built on.

## License

MIT
