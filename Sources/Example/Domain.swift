import Foundation
import Katana

// MARK: - Model

/// Plain value type — `Sendable` because every field is `Sendable`.
struct Todo: Sendable, Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
}

// MARK: - Repository

/// Source of truth for todos. An `actor` is implicitly `Sendable`, so it slots
/// into the default singleton scope and serialises every state mutation for
/// free — no locks, no `@unchecked` escape hatches.
@Injectable
actor TodoRepository {
    private var storage: [Todo] = []
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func all() -> [Todo] { storage }

    @discardableResult
    func add(title: String) -> Todo {
        let todo = Todo(id: UUID(), title: title, isCompleted: false)
        storage.append(todo)
        logger.log("repo +\"\(title)\"")
        return todo
    }

    func toggle(_ id: UUID) {
        guard let idx = storage.firstIndex(where: { $0.id == id }) else { return }
        storage[idx].isCompleted.toggle()
        logger.log("repo toggle \(storage[idx].title) → \(storage[idx].isCompleted)")
    }
}
