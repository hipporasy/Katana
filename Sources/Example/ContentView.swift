#if canImport(SwiftUI)
import SwiftUI
import Katana

/// MVVM view. `@App.Inject` is the macro-generated typed property wrapper —
/// it knows the App graph at compile time, so resolving an unregistered type
/// would be a compile error. No `Container`, no manual `resolve`, no per-type
/// `.environment(...)` plumbing.
@available(macOS 14, iOS 17, *)
struct ContentView: View {
    @App.Inject var viewModel: TodoListViewModel
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("New todo…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let title = draft
                    draft = ""
                    Task { await viewModel.add(title: title) }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            List(viewModel.todos) { todo in
                HStack {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    Text(todo.title)
                        .strikethrough(todo.isCompleted)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { Task { await viewModel.toggle(todo.id) } }
            }

            if viewModel.isLoading {
                ProgressView().padding()
            }
        }
        .task { await viewModel.load() }
    }
}

/// Drop-in SwiftUI app entry point — the composition root.
///
/// The `App` graph is built and snapshot once at launch, then installed in
/// the environment with `.katana(snapshot)`. Every descendant view reads its
/// dependencies with `@App.Inject` — compile-checked against the type list,
/// no per-VM `.environment(...)` call regardless of how many view models the
/// graph holds.
///
/// ```swift
/// @main
/// struct ExampleApp: SwiftUI.App {
///     @State private var snapshot: App.Snapshot?
///
///     var body: some Scene {
///         WindowGroup {
///             if let snapshot {
///                 ContentView().katana(snapshot)
///             } else {
///                 ProgressView().task {
///                     snapshot = await App().snapshot()
///                 }
///             }
///         }
///     }
/// }
/// ```
#endif
