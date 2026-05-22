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
    let viewModel = await app.resolve(TodoListViewModel.self)

    await viewModel.add(title: "Write MVVM example")
    await viewModel.add(title: "Ship Katana 0.2")
    await viewModel.add(title: "   ")
    await viewModel.add(title: "Sleep")

    if let firstId = await viewModel.todos.first?.id {
        await viewModel.toggle(firstId)
    }

    let todos = await viewModel.todos
    print("\n— Todos —")
    for todo in todos {
        print(" \(todo.isCompleted ? "[x]" : "[ ]") \(todo.title)")
    }

    let snap = await app.snapshot()
    let vmFromSnap = snap.resolve(TodoListViewModel.self)
    print("\nsnapshot returns the same VM:", viewModel === vmFromSnap)
}
