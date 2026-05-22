import XCTest
@testable import KatanaCodegenCore

final class ScannerTests: XCTestCase {

    // MARK: - @Module

    func testExtractsModuleDecl() {
        let scanner = Scanner()
        scanner.scan(source: """
        import Katana
        @Module(Logger.self, Network.self)
        enum ServiceModule {}
        """, path: "ServiceModule.swift")

        XCTAssertEqual(scanner.modules.count, 1)
        let mod = scanner.modules["ServiceModule"]
        XCTAssertNotNil(mod)
        XCTAssertEqual(mod?.types, ["Logger", "Network"])
        XCTAssertEqual(mod?.path, "ServiceModule.swift")
    }

    func testIgnoresEnumsWithoutModuleAttribute() {
        let scanner = Scanner()
        scanner.scan(source: """
        enum NotAModule {
            case one, two
        }
        """, path: "x.swift")
        XCTAssertTrue(scanner.modules.isEmpty)
    }

    func testHandlesEmptyModule() {
        let scanner = Scanner()
        scanner.scan(source: """
        @Module
        enum Empty {}
        """, path: "x.swift")
        XCTAssertEqual(scanner.modules["Empty"]?.types, [])
    }

    // MARK: - @Container

    func testExtractsContainerDecl() {
        let scanner = Scanner()
        scanner.scan(source: """
        @Container(modules: [ServiceModule.self, RepositoryModule.self])
        public final class App {}
        """, path: "App.swift")

        XCTAssertEqual(scanner.containers.count, 1)
        let container = scanner.containers[0]
        XCTAssertEqual(container.name, "App")
        XCTAssertEqual(container.scope, "default")     // omitted → default
        XCTAssertEqual(container.modules, ["ServiceModule", "RepositoryModule"])
        XCTAssertEqual(container.accessLevel, "public")
        XCTAssertNil(container.availability)
        XCTAssertFalse(container.isTest)
    }

    func testExtractsContainerScope() {
        let scanner = Scanner()
        scanner.scan(source: """
        @Container(scope: .checkout, modules: [CheckoutModule.self])
        final class CheckoutGraph {}
        """, path: "Checkout.swift")

        XCTAssertEqual(scanner.containers.first?.scope, "checkout")
        XCTAssertEqual(scanner.containers.first?.name, "CheckoutGraph")
    }

    func testCapturesAvailability() {
        let scanner = Scanner()
        scanner.scan(source: """
        @available(macOS 14, iOS 17, *)
        @Container(modules: [ServiceModule.self])
        final class App {}
        """, path: "App.swift")

        XCTAssertEqual(scanner.containers.first?.availability, "@available(macOS 14, iOS 17, *)")
        XCTAssertEqual(scanner.containers.first?.accessLevel, "")
    }

    // MARK: - @TestContainer

    func testExtractsTestContainerDecl() {
        let scanner = Scanner()
        scanner.scan(source: """
        @TestContainer(modules: [ServiceModule.self])
        final class TestApp {}
        """, path: "TestApp.swift")

        XCTAssertEqual(scanner.containers.count, 1)
        let container = scanner.containers[0]
        XCTAssertEqual(container.name, "TestApp")
        XCTAssertTrue(container.isTest)
    }

    // MARK: - @Scope

    func testExtractsScopeRegistry() {
        let scanner = Scanner()
        scanner.scan(source: """
        @Scope
        enum AppScope {
            case checkout
            case payment
        }
        """, path: "Scopes.swift")

        XCTAssertEqual(scanner.scopes.count, 1)
        XCTAssertEqual(scanner.scopes[0].name, "AppScope")
        XCTAssertEqual(scanner.scopes[0].cases, ["checkout", "payment"])
    }

    func testEmptyScopeRegistry() {
        let scanner = Scanner()
        scanner.scan(source: """
        @Scope
        enum AppScope {}
        """, path: "Scopes.swift")

        XCTAssertEqual(scanner.scopes.first?.cases, [])
    }

    // MARK: - Multi-file scan

    func testAggregatesAcrossSources() {
        let scanner = Scanner()
        scanner.scan(source: "@Module(Logger.self) enum ServiceModule {}", path: "Service.swift")
        scanner.scan(source: "@Module(TodoRepository.self) enum RepoModule {}", path: "Repo.swift")
        scanner.scan(source: "@Container(modules: [ServiceModule.self, RepoModule.self]) final class App {}", path: "App.swift")
        scanner.scan(source: "@Scope enum AppScope { case checkout }", path: "Scopes.swift")

        XCTAssertEqual(scanner.modules.count, 2)
        XCTAssertEqual(scanner.containers.count, 1)
        XCTAssertEqual(scanner.containers[0].modules, ["ServiceModule", "RepoModule"])
        XCTAssertEqual(scanner.scopes.count, 1)
        XCTAssertEqual(scanner.scopes[0].cases, ["checkout"])
    }
}
