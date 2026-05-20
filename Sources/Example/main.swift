import Foundation
import Katana

if #available(macOS 14, iOS 17, *) {
    await runExample()
} else {
    print("Example requires macOS 14+ (uses @Observable).")
}

@available(macOS 14, iOS 17, *)
func runExample() async {
    let app = await App()
    let viewModel = await app.resolve(TodoListViewModel.self)   // compile-checked

    // Drive the view model the way a SwiftUI view would.
    await viewModel.add(title: "Write MVVM example")
    await viewModel.add(title: "Ship Katana 0.2")
    await viewModel.add(title: "   ") // dropped by guard
    await viewModel.add(title: "Sleep")

    if let firstId = await viewModel.todos.first?.id {
        await viewModel.toggle(firstId)
    }

    let todos = await viewModel.todos
    print("\n— Todos —")
    for todo in todos {
        print(" \(todo.isCompleted ? "[x]" : "[ ]") \(todo.title)")
    }

    // The typed snapshot — sync, Sendable, ready for SwiftUI's environment.
    let snap = await app.snapshot()
    let vmFromSnap = snap.resolve(TodoListViewModel.self)         // compile-checked
    print("\nsnapshot returns the same VM:", viewModel === vmFromSnap)

    // Compile-time-safety smoke test (uncomment to confirm the macro catches it):
    // _ = await app.resolve(String.self)        // ❌ no matching resolve overload
    // _ = snap.resolve(String.self)             // ❌ no matching resolve overload
}
