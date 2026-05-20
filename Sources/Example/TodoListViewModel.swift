import Foundation
import Katana

/// MVVM view model.
///
/// - `@MainActor` keeps state mutation on the UI thread and makes the class
///   implicitly `Sendable`, satisfying singleton scope without extra work.
/// - `@Observable` plugs into SwiftUI's tracking system so views re-render on
///   property changes.
/// - `@Injectable` synthesises the container wiring for `init`'s dependencies.
@available(macOS 14, iOS 17, *)
@MainActor
@Observable
@Injectable
final class TodoListViewModel {
    private let repository: TodoRepository
    private let logger: Logger

    var todos: [Todo] = []
    var isLoading: Bool = false

    init(repository: TodoRepository, logger: Logger) {
        self.repository = repository
        self.logger = logger
    }

    func load() async {
        isLoading = true
        todos = await repository.all()
        isLoading = false
    }

    func add(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.log("vm rejected empty title")
            return
        }
        await repository.add(title: trimmed)
        await load()
    }

    func toggle(_ id: UUID) async {
        await repository.toggle(id)
        await load()
    }
}
