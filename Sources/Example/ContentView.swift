#if canImport(SwiftUI)
import SwiftUI
import Katana

@available(macOS 14, iOS 17, *)
struct ContentView: View {
    @Inject var viewModel: TodoListViewModel
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

/// Composition root example:
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
