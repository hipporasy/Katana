# Multiple Containers

Most apps need one container. Some don't. This guide covers the multi-container patterns Katana supports, the trade-offs, and where the seams are if you need to push further.

## When you actually need more than one

- **Feature-scoped graphs.** A `Checkout` flow has its own short-lived dependencies (cart, payment session) that shouldn't outlive the flow. Compose them in a `Checkout` container, install it only inside the checkout subtree, tear down on exit.
- **Plugin / module boundaries.** A host app + plugin SDK might each ship their own typed container.
- **Test surface.** `@TestContainer` is the test-target peer of `@Container`. Not really "multi-container" in the runtime sense.

If your reason is "I want different lifetimes," check first whether `.transient` (the injectable scope) solves it. Container multiplicity should be the answer to "different *scope of validity*," not "different *creation policy*."

## The shape of a multi-container app

Custom scopes are declared once with `@Scope`; each `@Container` binds to a scope.

```swift
@Scope
enum AppScope {
    case checkout
    case account
}

@Container(modules: [ServiceModule.self, AuthModule.self])
final class App {}                                          // implicit .default

@Container(scope: .checkout, modules: [CheckoutModule.self])
final class Checkout {}

@Container(scope: .account, modules: [AccountModule.self])
final class Account {}
```

Each graph is its own typed class. The build plugin emits:

- `App.Snapshot`, `Checkout.Snapshot`, `Account.Snapshot` — independent typed resolvers
- `\.katanaDefault`, `\.checkout`, `\.account` — independent `EnvironmentValues` slots
- Three `View.katana(_:)` overloads, picked by snapshot type
- `Inject.init()` only for `App` (the `.default` graph) — bare `@Inject` is reserved for it

If two `@Container`s bind to the same scope, the plugin emits a build error pointing at both.

## SwiftUI plumbing — generated, not manual

For every `@Container`, the plugin generates:

```swift
// Plugin-emitted for `Checkout`:
private struct __Katana_Checkout_SnapshotKey: EnvironmentKey {
    static let defaultValue: (any Resolver)? = nil
}

extension EnvironmentValues {
    var checkout: (any Resolver)? { ... }
}

extension View {
    func katana(_ snapshot: Checkout.Snapshot) -> some View {
        environment(\.checkout, snapshot)
    }
}
```

You install with `.katana(snapshot)` regardless of which graph — the overload is picked by snapshot type. Reading happens with `@Inject(\.<scope>)`:

```swift
struct PayButton: View {
    @Inject var network: Network                            // .default graph
    @Inject(\.checkout) var vm: CheckoutViewModel           // .checkout graph

    var body: some View { ... }
}
```

Typing `@Inject(\.chekcout)` (with a typo) is a compile error — `ContainerScope.chekcout` doesn't exist, and the keypath can't resolve.

## Install pattern

Root tree gets the primary graph:

```swift
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
```

A feature subtree adds its graph only where it's valid:

```swift
struct CheckoutFlow: View {
    @Inject var session: AuthSession
    @State private var checkout: Checkout.Snapshot?

    var body: some View {
        if let checkout {
            CheckoutRootView().katana(checkout)
        } else {
            ProgressView().task {
                // Pass the session from App into Checkout's graph via the closure init.
                checkout = await Checkout { c in
                    await c.override(AuthSession.self, with: session)
                }.snapshot()
            }
        }
    }
}
```

When `CheckoutFlow` disappears, `checkout` deallocates — the graph's lifetime tracks the view's. No global registry to leak.

## Passing dependencies between graphs

The seam is the **closure init**, not double-registration. If `Checkout` needs the `App` graph's `AuthSession`, the parent view resolves it from `App.Snapshot` and overrides the registration in `Checkout`:

```swift
let app = await App()
let session = await app.resolve(AuthSession.self)

let checkout = await Checkout { c in
    await c.override(AuthSession.self, with: session)
}
```

This is type-checked: `App` must register `AuthSession` (via some `@Module`), `Checkout` must register `AuthSession` (so the override matches), and the instance flows from one to the other explicitly.

## Compile-time safety still applies

Adding a second graph doesn't soften the compile-time guarantees:

- `@Inject var vm: CheckoutViewModel` (bare → `.default`) → **compile error** if `CheckoutViewModel` isn't in `App.Snapshot`.
- `@Inject(\.checkout) var session: AuthSession` → works only if `Checkout`'s modules register `AuthSession`.

The `@Module` set per `@Container` is the safety contract. Refactor a dep into the wrong graph and the build catches you.

## Anti-patterns

- **Don't** install the same snapshot at two unrelated scopes — you'll have two independent graphs of "the same" services with separate singleton state.
- **Don't** double-register a singleton in two graphs and hope they share — they won't. Pick one graph as the owner, pass the resolved instance into the other via override.
- **Don't** mix `@Inject` (no keypath) and `@Inject(\.<scope>)` arbitrarily. Use bare `@Inject` only for dependencies in the `.default` graph; reach for the explicit form when crossing graph boundaries.

## Notes on test targets

Test targets that use `@testable import` to reach production types must re-declare their own `@Module` enums in the test target, because the build plugin scans per target. The scanner replays imports in the generated file, so `@testable import Example` in your test file propagates to `KatanaGenerated.swift` automatically.

To avoid `EnvironmentValues.katanaDefault` colliding between the production target's emission and the test target's emission, put `@TestContainer` on a custom scope:

```swift
// In Tests/ExampleTests/
@Scope enum ExampleTestsScope { case test }

@TestContainer(scope: .test, modules: [TestAppModule.self])
final class TestApp {}
```

Tests then call `app.resolve(...)` / `app.override(...)` directly — they don't go through SwiftUI's environment.

## See also

- [`mvvm.md`](mvvm.md) — single-graph walkthrough with the example project
- [`design.md`](design.md) — DI architecture, macro contract, scope rules
- [`modules.md`](modules.md) — `@Module` composition and the codegen plugin
- [`swift6.md`](swift6.md) — Swift 6 concurrency rules
