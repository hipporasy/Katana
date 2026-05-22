#if canImport(SwiftUI)
import SwiftUI

/// Protocol every `@Container`-annotated class conforms to (via plugin-emitted
/// extension). Lets a generic SwiftUI helper construct the graph, eagerly
/// snapshot it, and install the snapshot in the right `EnvironmentValues`
/// slot without per-app boilerplate.
///
/// Users rarely reference this directly — they call `.katana(MyGraph.self)`
/// on a view and the framework does the rest.
public protocol KatanaGraph: AnyObject {
    associatedtype Snapshot: Resolver

    /// Builds the inner `Container`, registers every type, then runs the
    /// optional override closure. Plugin-emitted on every `@Container`.
    init(_ customize: (@Sendable (Container) async -> Void)?) async

    /// Eagerly resolves every singleton and returns the typed snapshot.
    /// Plugin-emitted on every `@Container`.
    func snapshot() async -> Snapshot

    /// The `EnvironmentValues` slot this graph installs into. `.default`-scoped
    /// graphs use `\.katanaDefault`; custom-scoped graphs use the scope name.
    /// Plugin-emitted as part of the conformance.
    static var environmentKeyPath: WritableKeyPath<EnvironmentValues, (any Resolver)?> { get }
}

extension View {
    /// Bootstraps `Graph`, snapshots it, and installs the result in the
    /// SwiftUI environment — all in one line. Replaces the manual
    /// `@State` + `if let` + `.task` dance every Katana app would otherwise write.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: SwiftUI.App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             RootView().katana(AppGraph.self)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Pass a `customize` closure to apply overrides at construction time:
    ///
    /// ```swift
    /// RootView().katana(AppGraph.self) { container in
    ///     await container.override(Logger.self, with: ProductionLogger())
    /// }
    /// ```
    ///
    /// While the graph is being built, an empty `Color.clear` is shown — pass
    /// `loading:` to customise:
    ///
    /// ```swift
    /// RootView().katana(AppGraph.self, loading: { ProgressView() })
    /// ```
    public func katana<Graph: KatanaGraph>(
        _ graph: Graph.Type,
        loading: @escaping () -> some View = { Color.clear },
        customize: (@Sendable (Container) async -> Void)? = nil
    ) -> some View {
        modifier(_KatanaInstallModifier(graph: graph, customize: customize, loading: loading))
    }
}

private struct _KatanaInstallModifier<Graph: KatanaGraph, Loading: View>: ViewModifier {
    let graph: Graph.Type
    let customize: (@Sendable (Container) async -> Void)?
    let loading: () -> Loading
    @State private var snapshot: Graph.Snapshot?

    func body(content: Content) -> some View {
        Group {
            if let snapshot {
                content.environment(Graph.environmentKeyPath, snapshot)
            } else {
                loading()
            }
        }
        .task {
            let g = await Graph.init(customize)
            snapshot = await g.snapshot()
        }
    }
}
#endif
