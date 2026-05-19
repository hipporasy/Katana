# ``Katana``

A Swift 6 macro-based dependency injection framework. Dagger/Hilt semantics, Swift idioms, minimal runtime.

## Overview

Katana centers on three pieces:

- **``Injectable``** — the protocol every container-resolvable type conforms to.
- **``Container``** — an `actor` registry that caches singletons and produces transient instances.
- **`@Injectable`** — a macro that synthesizes `Injectable` conformance from a type's primary initializer.

```swift
@Injectable
final class AuthService: Sendable {
    init(network: NetworkService, logger: Logger) { … }
}

let container = Container()
await container.register(AuthService.self)

let auth = await container.resolve(AuthService.self)
```

Resolution is `async` because the container is an actor — Swift 6 strict concurrency is enforced top-to-bottom, with no `@unchecked Sendable` escape hatches.

## Scopes

Two scopes are supported, selected per-type via the macro:

| Scope             | Caching                      | Sendability requirement | Macro                              |
|-------------------|------------------------------|-------------------------|------------------------------------|
| `.singleton` (default) | Cached, same instance returned | Type must be `Sendable` | `@Injectable` or `@Injectable(scope: .singleton)` |
| `.transient`           | Fresh instance per resolve   | Non-`Sendable` allowed via `sending` (SE-0430) | `@Injectable(scope: .transient)` |

`@Observable` and `@MainActor` classes are implicitly `Sendable`, so they slot in as singletons with no extra work.

## Topics

### Defining injectable types

- ``Injectable``
- ``Scope``

### The container

- ``Container``

### Concurrency model

The macro-generated `resolve(from:)` is `nonisolated async`. With Swift 6.2's `NonisolatedNonsendingByDefault`, it runs on the caller's actor, so injection across `@MainActor` and other actor boundaries works without explicit hops.

The protocol returns `sending Self` uniformly. For `Sendable` singletons that is a harmless no-op; for non-`Sendable` transients it enforces single-owner transfer at the call site.

### Custom factories

Pass an explicit factory closure when the default macro-generated wiring isn't enough — e.g., for conditional construction or wrapping a third-party type:

```swift
await container.register(Network.self) { container in
    await Network(config: container.resolve(Config.self))
}
```

The closure is `@Sendable` and may itself `await` further resolutions.

### Manual conformance

Leaf types without injectable dependencies can conform manually instead of using the macro — useful for wrapping system types:

```swift
extension URLSession: Injectable {
    static func resolve(from container: Container) async -> sending Self {
        Self.shared as! Self
    }
}
```
