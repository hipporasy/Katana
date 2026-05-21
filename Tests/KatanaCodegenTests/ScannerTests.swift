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
        // Attribute exists but no args — Module is still recorded with empty type list.
        XCTAssertEqual(scanner.modules["Empty"]?.types, [])
    }

    // MARK: - @KatanaApp

    func testExtractsAppDecl() {
        let scanner = Scanner()
        scanner.scan(source: """
        @KatanaApp(modules: [ServiceModule.self, RepositoryModule.self])
        public final class App {}
        """, path: "App.swift")

        XCTAssertEqual(scanner.apps.count, 1)
        let app = scanner.apps[0]
        XCTAssertEqual(app.name, "App")
        XCTAssertEqual(app.modules, ["ServiceModule", "RepositoryModule"])
        XCTAssertEqual(app.accessLevel, "public")
        XCTAssertNil(app.availability)
    }

    func testCapturesAvailability() {
        let scanner = Scanner()
        scanner.scan(source: """
        @available(macOS 14, iOS 17, *)
        @KatanaApp(modules: [ServiceModule.self])
        final class App {}
        """, path: "App.swift")

        XCTAssertEqual(scanner.apps.first?.availability, "@available(macOS 14, iOS 17, *)")
        XCTAssertEqual(scanner.apps.first?.accessLevel, "")
    }

    // MARK: - @KatanaTestApp

    func testExtractsTestAppDecl() {
        let scanner = Scanner()
        scanner.scan(source: """
        @KatanaTestApp(of: App.self)
        final class TestApp {}
        """, path: "TestApp.swift")

        XCTAssertEqual(scanner.testApps.count, 1)
        XCTAssertEqual(scanner.testApps[0].name, "TestApp")
        XCTAssertEqual(scanner.testApps[0].productionApp, "App")
    }

    // MARK: - Multi-file scan

    func testAggregatesAcrossSources() {
        let scanner = Scanner()
        scanner.scan(source: "@Module(Logger.self) enum ServiceModule {}", path: "Service.swift")
        scanner.scan(source: "@Module(TodoRepository.self) enum RepoModule {}", path: "Repo.swift")
        scanner.scan(source: "@KatanaApp(modules: [ServiceModule.self, RepoModule.self]) final class App {}", path: "App.swift")

        XCTAssertEqual(scanner.modules.count, 2)
        XCTAssertEqual(scanner.apps.count, 1)
        XCTAssertEqual(scanner.apps[0].modules, ["ServiceModule", "RepoModule"])
    }
}
