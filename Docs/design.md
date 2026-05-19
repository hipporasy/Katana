# Katana Design Rules

## Core Concept

Katana is a Swift macro-based DI framework. The macro generates boilerplate; the runtime is minimal. Think Dagger/Hilt semantics, Swift idioms.

## The Three Pieces

### 1. `@Injectable` macro — `@attached(extension)`

Marks a type as resolvable by the container. The macro inspects the primary `init` and generates:

```swift
// You write:
@Injectable
final class AuthService {
    init(network: NetworkService, logger: LoggerService) { ... }
}

// Macro expands to:
extension AuthService: Injectable {
    static func resolve(from container: Container) async -> Self {
        await Self(
            network: container.resolve(NetworkService.self),
            logger: container.resolve(LoggerService.self)
        )
    }
}
```

### 2. `Injectable` protocol

```swift
public protocol Injectable {
    static func resolve(from container: Container) async -> Self
}
```

Every `@Injectable` type gets this conformance automatically. Leaf types (no injectable dependencies) can conform manually.

### 3. `Container` — the runtime registry

`Container` is an **`actor`**. This is intentional and non-negotiable (see `swift6.md`). Resolution requires `await`.

```swift
let container = Container()
await container.register(NetworkService.self)
await container.register(AuthService.self)  // resolves NetworkService automatically

let auth = await container.resolve(AuthService.self)
```

## Scopes

Katana supports both scopes. Scope determines the Sendable requirement.

### Singleton (default)

The container caches the instance and returns the same reference on every resolve. Because the container holds *and* shares the reference, the type **must be `Sendable`**.

```swift
@Injectable                      // singleton by default
@Injectable(scope: .singleton)   // explicit

final class NetworkService: Sendable { ... }  // ✅
@Observable final class AppState { ... }      // ✅ @Observable is implicitly Sendable
@MainActor final class ViewModel { ... }      // ✅ @MainActor is implicitly Sendable
```

### Transient

A new instance is created on every resolve. The container creates the value and **transfers ownership** to the caller via `sending` (SE-0430). The type does **not** need to be `Sendable` — the compiler enforces that only one owner exists at a time.

```swift
@Injectable(scope: .transient)

final class RequestContext { ... }  // ✅ non-Sendable is fine
```

### Resolution signatures

```swift
// Singleton — T must be Sendable
func resolve<T: Injectable & Sendable>(_ type: T.Type) async -> T

// Transient — ownership transferred, non-Sendable OK
func resolve<T: Injectable>(_ type: T.Type) async -> sending T
```

The macro generates `resolve(from:)` using the same split — singleton conformance constrains `Self: Sendable`, transient uses `sending Self`.

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

## What the Macro Must NOT Do

- Do not generate `@MainActor` isolation on the `resolve` method — callers own their isolation context.
- Do not access stored properties of the type being expanded — only inspect `init` parameter types and labels.
- Do not support multiple `init` overloads automatically — if a type has multiple inits, the macro requires `@Injectable` to specify which one (TBD API), or it picks the first designated initializer.
- Do not modify the type's own definition — only generate `extension` conformances (peer/extension macros only, never member macros that mutate the type body).

## Error Cases

If `@Injectable` is applied to a type with no `init` parameters, generate a trivial conformance:

```swift
extension LoggerService: Injectable {
    static func resolve(from container: Container) async -> Self { Self() }
}
```

If `@Injectable` is applied to a type that can't be initialized (e.g., abstract protocol), emit a compile-time diagnostic.
