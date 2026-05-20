import Foundation
import Katana
#if canImport(SwiftUI)
import SwiftUI
#endif

/// The dependency graph for the Example.
///
/// `@Container` reads the type list and synthesises:
///   - `init(_:)` that registers every type and runs an optional override closure
///   - typed `resolve(_:)` overloads — compile-checked against the type list
///   - nested `App.Snapshot` conforming to `Resolver`
///   - `snapshot() async -> Snapshot`
///   - nested `@propertyWrapper App.Inject` for SwiftUI
///
/// Adding/removing a type from the `@Container(...)` arguments is the **only**
/// place registrations change. Every consumer site is then compile-checked.
@available(macOS 14, iOS 17, *)
@Container(
    Logger.self,
    TodoRepository.self,
    TodoListViewModel.self
)
final class App {}
