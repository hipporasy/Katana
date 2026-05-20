import Foundation
import Testing
import Katana
@testable import Example
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Test peer of `App`. Same type list — `@TestContainer` adds post-construction
/// `override(_:with:)` and `override(_:factory:)` methods plus a
/// `TestContainerMarker` conformance. Compile-time safety on `resolve` is
/// identical to `App`'s.
@available(macOS 14, iOS 17, *)
@TestContainer(
    Logger.self,
    TodoRepository.self,
    TodoListViewModel.self
)
final class TestApp {}

@MainActor
@Suite("MVVM Example")
struct ExampleTests {

    // MARK: - Wiring

    @Test func resolvesViewModelFromTestApp() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp()
        let viewModel = await app.resolve(TodoListViewModel.self)
        await viewModel.load()
        #expect(viewModel.todos.isEmpty)
    }

    @Test func singletonScopeReturnsSameInstanceWithinAnApp() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp()
        let a = await app.resolve(TodoListViewModel.self)
        let b = await app.resolve(TodoListViewModel.self)
        #expect(a === b)
    }

    @Test func twoAppsAreFullyIndependent() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let appA = await TestApp()
        let appB = await TestApp()

        let vmA = await appA.resolve(TodoListViewModel.self)
        let vmB = await appB.resolve(TodoListViewModel.self)
        await vmA.add(title: "Only in A")

        #expect(vmA !== vmB)
        #expect(vmA.todos.count == 1)
        #expect(vmB.todos.isEmpty)
    }

    // MARK: - Behaviour

    @Test func addsAndTogglesTodo() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp()
        let viewModel = await app.resolve(TodoListViewModel.self)

        await viewModel.add(title: "Test")
        #expect(viewModel.todos.count == 1)
        #expect(viewModel.todos.first?.isCompleted == false)

        let id = try #require(viewModel.todos.first?.id)
        await viewModel.toggle(id)
        #expect(viewModel.todos.first?.isCompleted == true)
    }

    @Test func rejectsBlankTitle() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp()
        let viewModel = await app.resolve(TodoListViewModel.self)

        await viewModel.add(title: "   ")
        await viewModel.add(title: "")

        #expect(viewModel.todos.isEmpty)
    }

    // MARK: - Snapshot (typed sync resolver for SwiftUI @App.Inject)

    @Test func snapshotReturnsTheSameInstanceAsContainer() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp()
        let snapshot = await app.snapshot()

        let viaApp = await app.resolve(TodoListViewModel.self)
        let viaSnapshot = snapshot.resolve(TodoListViewModel.self)
        #expect(viaApp === viaSnapshot)

        let repoViaApp = await app.resolve(TodoRepository.self)
        let repoViaSnapshot = snapshot.resolve(TodoRepository.self)
        #expect(repoViaApp === repoViaSnapshot)
    }

    @Test func snapshotReflectsOverrides() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let spy = SpyLogger()
        let app = await TestApp { c in
            await c.override(Logger.self, with: spy)
        }

        let snapshot = await app.snapshot()
        let viaSnapshot = snapshot.resolve(Logger.self)
        #expect(viaSnapshot === spy)
    }

    // MARK: - Overrides (the @TestContainer seam)

    /// Closure init — overrides applied during construction.
    @Test func overrideRepositoryPreseedsStateViaClosure() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp { c in
            await c.override(TodoRepository.self) { container in
                let logger = await container.resolve(Logger.self)
                let repo = TodoRepository(logger: logger)
                await repo.add(title: "Seed A")
                await repo.add(title: "Seed B")
                return repo
            }
        }

        let viewModel = await app.resolve(TodoListViewModel.self)
        await viewModel.load()

        let titles = viewModel.todos.map { $0.title }
        #expect(viewModel.todos.count == 2)
        #expect(titles == ["Seed A", "Seed B"])
    }

    /// Post-construction `override(_:with:)` — `@TestContainer`-specific
    /// ergonomic. Useful when you want to build the graph first, then swap
    /// one dep for a particular test.
    @Test func overrideLoggerPostConstruction() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp()
        let spy = SpyLogger()
        await app.override(Logger.self, with: spy)

        let viewModel = await app.resolve(TodoListViewModel.self)
        await viewModel.add(title: "logged")

        #expect(spy.captured.contains(where: { $0.contains("logged") }))
    }

    /// Confirms post-construction override clears any prior cached singleton.
    @Test func overrideAfterPriorResolveTakesEffect() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let app = await TestApp()
        let original = await app.resolve(Logger.self)

        let spy = SpyLogger()
        await app.override(Logger.self, with: spy)

        let afterOverride = await app.resolve(Logger.self)
        #expect(afterOverride === spy)
        #expect(afterOverride !== original)
    }

    /// `@TestContainer` emits `TestContainerMarker` conformance so lint
    /// scripts can find every test container in the codebase.
    @Test func testAppConformsToTestContainerMarker() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        // Pure type-system assertion — if TestApp didn't conform, this
        // wouldn't compile.
        let _: any TestContainerMarker = await TestApp()
    }
}

/// Test double. `Logger` is non-final in this example so it can be subclassed
/// for spying. `required init()` is needed because the macro-generated
/// `Self()` constructor in `Logger.resolve(from:)` must be inheritable.
final class SpyLogger: Logger, @unchecked Sendable {
    private let lock = NSLock()
    private var _captured: [String] = []

    required init() { super.init() }

    var captured: [String] {
        lock.lock(); defer { lock.unlock() }
        return _captured
    }

    override func log(_ msg: String) {
        lock.lock(); defer { lock.unlock() }
        _captured.append(msg)
    }
}
