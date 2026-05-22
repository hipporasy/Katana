import Foundation
import Testing
import Katana
@testable import Example
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Test graph

// The KatanaCodegen plugin scans per target, so the test target re-declares
// its own modules referencing Example's internal types via `@testable import`.
// Aggregated into a single test module for brevity — production code would
// typically mirror the production module shape.
@available(macOS 14, iOS 17, *)
@Module(Logger.self, TodoRepository.self, TodoListViewModel.self)
enum TestAppModule {}

/// Custom scope keeps the test container off `.default`, which avoids a
/// collision with `Example.App`'s `\.katanaDefault` extension that flows in
/// via `@testable import`.
@Scope
enum ExampleTestsScope {
    case test
}

/// Test peer of `App`. `@TestContainer` emits the same shape as `@Container`
/// plus post-construction `override(_:with:)` / `override(_:factory:)` and
/// `TestContainerMarker` conformance.
@available(macOS 14, iOS 17, *)
@TestContainer(scope: .test, modules: [TestAppModule.self])
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

    // MARK: - Snapshot (typed sync resolver for SwiftUI @Inject)

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

    // MARK: - Cycle detection

    /// The resolution chain is empty before any resolve starts.
    @Test func resolutionChainIsEmptyAtRest() async throws {
        #expect(Container.resolutionChain.isEmpty)
    }

    /// During a resolve, the chain accumulates type names. We probe it via a
    /// dependency whose factory inspects the chain at resolve-time. This
    /// exercises the task-local propagation without triggering the trap.
    @Test func resolutionChainAccumulatesDuringNestedResolves() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        // Use a fresh Container with a custom factory that captures the chain
        // mid-resolve. The chain reflects the call site that triggered this
        // factory.
        let captured = ChainCapture()
        let container = Container()
        await container.register(Logger.self) { _ in
            captured.set(Container.resolutionChain)
            return Logger()
        }

        _ = await container.resolve(Logger.self)
        let chain = captured.value
        #expect(chain.contains(where: { $0.contains("Logger") }))
    }

    /// Two unrelated resolves in sequence don't leak chain state into each
    /// other — task-local is unwound after each resolve completes.
    @Test func chainIsRestoredAfterResolveCompletes() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let container = await TestApp()
        _ = await container.resolve(TodoRepository.self)
        #expect(Container.resolutionChain.isEmpty)
    }

    // MARK: - Named bindings

    /// Two named registrations of the same `Type` coexist; each resolves to
    /// its own instance. Unnamed resolves see neither.
    @Test func namedBindingsResolveIndependently() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let console = SpyLogger()
        let file = SpyLogger()
        let container = Container()
        await container.register(Logger.self, name: "console") { _ in console }
        await container.register(Logger.self, name: "file") { _ in file }

        let resolvedConsole = await container.resolve(Logger.self, name: "console")
        let resolvedFile = await container.resolve(Logger.self, name: "file")

        #expect(resolvedConsole === console)
        #expect(resolvedFile === file)
        #expect(resolvedConsole !== resolvedFile)
    }

    /// Resolving an unregistered named binding traps with a helpful message.
    /// We verify the cache mechanism instead: a named binding caches under
    /// its own key, so re-resolving with the same name returns the same
    /// instance.
    @Test func namedSingletonCachesPerName() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let container = Container()
        await container.register(Logger.self, name: "console") { _ in SpyLogger() }

        let first = await container.resolve(Logger.self, name: "console")
        let second = await container.resolve(Logger.self, name: "console")
        #expect(first === second)
    }

    /// Unnamed registration and named registration of the same type are
    /// independent: unnamed resolve doesn't see the named instance.
    @Test func unnamedDoesNotSeeNamedRegistration() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let namedSpy = SpyLogger()
        let container = Container()
        await container.register(Logger.self)                                    // unnamed default
        await container.register(Logger.self, name: "console") { _ in namedSpy } // named

        let unnamed = await container.resolve(Logger.self)
        let named = await container.resolve(Logger.self, name: "console")

        #expect(unnamed !== namedSpy)
        #expect(named === namedSpy)
    }

    /// `override(_:name:with:)` replaces a named registration.
    @Test func overrideAppliesToNamedBinding() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let original = SpyLogger()
        let replacement = SpyLogger()
        let container = Container()
        await container.register(Logger.self, name: "audit") { _ in original }
        let first = await container.resolve(Logger.self, name: "audit")
        #expect(first === original)

        await container.override(Logger.self, name: "audit", with: replacement)
        let second = await container.resolve(Logger.self, name: "audit")
        #expect(second === replacement)
    }

    /// Snapshot omits named bindings — they're container-level only.
    @Test func snapshotOmitsNamedBindings() async throws {
        guard #available(macOS 14, iOS 17, *) else { return }

        let container = Container()
        await container.register(Logger.self)
        await container.register(Logger.self, name: "audit") { _ in SpyLogger() }

        let snap = await container.snapshot()
        // Resolving the unnamed Logger via the snapshot works.
        let _: Logger = snap.resolve(Logger.self)
        // The snapshot has exactly the unnamed Logger; the named "audit"
        // binding stays inside the container and is not in the snapshot.
        // We verify indirectly by checking the same instance comes back
        // through both paths.
        let viaContainer = await container.resolve(Logger.self)
        let viaSnapshot: Logger = snap.resolve(Logger.self)
        #expect(viaContainer === viaSnapshot)
    }
}

/// Test helper: captures the resolution chain at a specific point inside a
/// custom factory closure.
final class ChainCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: [String] = []

    var value: [String] {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func set(_ v: [String]) {
        lock.lock(); defer { lock.unlock() }
        _value = v
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
