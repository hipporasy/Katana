# Multiple Containers

Most apps need one container. Some don't. This guide covers the multi-container patterns Katana supports today, the trade-offs, and where the seams are if you need to push further.

## When you actually need more than one

- **Feature-scoped graphs.** A `Checkout` flow has its own short-lived dependencies (cart, payment session) that shouldn't outlive the flow. Compose them in a `Checkout` container, install it only inside the checkout subtree, tear down on exit.
- **Plugin / module boundaries.** A host app + plugin SDK might each ship their own typed container.
- **Test surface.** Already covered — `@TestContainer` is the test-target peer of `@Container`. Not really "multi-container" in the runtime sense.

If your reason is "I want different lifetimes," check first whether `.transient` scope solves it. Container multiplicity should be the answer to "different *scope of validity*," not "different *creation policy*."

## The shape of a multi-container app

Each graph is its own `@Container`-annotated class:

```swift
@Container(Logger.self, Network.self, AuthSession.self)
final class App {}

@Container(CartStore.self, PaymentClient.self, CheckoutViewModel.self)
final class Checkout {}
```

The macro generates **independent** types per graph: `App.Snapshot`, `App.Inject`, `Checkout.Snapshot`, `Checkout.Inject`. There's no cross-graph leakage at the type level.

## Today's environment plumbing (manual)

In v1, the `@Container` macro emits a single typed `Inject` that reads `\.katanaResolver` from the environment and downcasts to `<ClassName>.Snapshot`. For a single-graph app, this is invisible — you install the snapshot with `.katana(snapshot)` and `@App.Inject` works.

For **multiple snapshots in flight at once**, the shared key is insufficient: only one snapshot fits per env key. You add per-graph keys manually:

```swift
// One-time setup per additional graph:
extension EnvironmentValues {
    @Entry var checkoutSnapshot: Checkout.Snapshot?
}
```

And a per-graph view modifier + property wrapper that reads the dedicated key:

```swift
extension View {
    func checkout(_ snapshot: Checkout.Snapshot) -> some View {
        environment(\.checkoutSnapshot, snapshot)
    }
}

@propertyWrapper
struct CheckoutInject<Value: Sendable>: DynamicProperty {
    @Environment(\.checkoutSnapshot) private var snapshot
    var wrappedValue: Value {
        guard let snapshot else {
            preconditionFailure("Checkout.Snapshot not installed in this subtree.")
        }
        return snapshot.resolve(Value.self)
    }
}
```

Use the primary graph as the default (`@App.Inject`) and the additional graph through the custom wrapper:

```swift
struct PayButton: View {
    @App.Inject var network: Network              // primary graph (shared env key)
    @CheckoutInject var vm: CheckoutViewModel     // feature graph (custom env key)

    var body: some View { ... }
}
```

This works today. The boilerplate is one `extension EnvironmentValues` and one custom property wrapper per additional graph. A future macro enhancement could generate both, but at the cost of additional macro surface area — see "Future work" below.

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
    @App.Inject var session: AuthSession
    @State private var checkout: Checkout.Snapshot?

    var body: some View {
        if let checkout {
            CheckoutRootView().checkout(checkout)
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

The proper seam is the **closure init**, not double-registration. If `Checkout` needs the `App` graph's `AuthSession`, the parent view resolves it from `App.Snapshot` and overrides the registration in `Checkout`:

```swift
let app = await App()
let session = await app.resolve(AuthSession.self)

let checkout = await Checkout { c in
    await c.override(AuthSession.self, with: session)
}
```

This is type-checked: `App` must register `AuthSession`, `Checkout` must register `AuthSession` (so the override matches), and the instance flows from one to the other explicitly.

## Compile-time safety still applies

Adding a second graph doesn't soften the compile-time guarantees:

- `@App.Inject var vm: CheckoutViewModel` → **compile error** (not in `App`'s type list).
- `@CheckoutInject var session: AuthSession` → only works if `AuthSession` is in `Checkout`'s type list.

The graph annotation is the safety contract. Refactor a dep into the wrong graph and the build catches you.

## Anti-patterns

- **Don't** install the same snapshot at two unrelated scopes — you'll have two independent graphs of "the same" services with separate singleton state.
- **Don't** double-register a singleton in two graphs and hope they share — they won't. Pick one graph as the owner, pass the resolved instance into the other via override.
- **Don't** use bare `@Inject` when more than one snapshot is in scope. The downcast targets *one* type; the wrong snapshot triggers a runtime trap with an unhelpful message.

## Future work

The manual env-key boilerplate above is real friction. A future macro enhancement could emit a peer `extension EnvironmentValues` + dedicated `Inject` per graph automatically, eliminating the one-off setup. This is gated on Swift's peer-macro restrictions at global scope (see `roadmap.md`).

Until then: one extension and one property wrapper per extra graph is the cost. For most apps, that's one graph total and zero boilerplate.

## See also

- [`mvvm.md`](mvvm.md) — single-graph walkthrough with the example project
- [`roadmap.md`](roadmap.md) — phased plan including future multi-graph improvements
- [`design.md`](design.md) — DI architecture, macro contract, scope rules
- [`swift6.md`](swift6.md) — Swift 6 concurrency rules
