import XCTest
@testable import KatanaCodegenCore

final class EmitterTests: XCTestCase {

    // MARK: - App emission

    func testEmitsResolveOverloadPerType() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger", "Network"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["Service"])]
        let output = Emitter.emit(apps: apps, testApps: [], modules: modules)

        XCTAssertTrue(output.contains("func resolve(_: Logger.Type) async -> Logger"))
        XCTAssertTrue(output.contains("func resolve(_: Network.Type) async -> Network"))
        XCTAssertTrue(output.contains("await inner.register(Logger.self)"))
        XCTAssertTrue(output.contains("await inner.register(Network.self)"))
    }

    func testEmitsTypedSnapshotStruct() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["Service"])]
        let output = Emitter.emit(apps: apps, testApps: [], modules: modules)

        XCTAssertTrue(output.contains("struct Snapshot: Resolver"))
        XCTAssertTrue(output.contains("let logger: Logger"))
        XCTAssertTrue(output.contains("func resolve(_: Logger.Type) -> Logger { logger }"))
        XCTAssertTrue(output.contains("ObjectIdentifier(Logger.self)"))
    }

    func testEmitsSwiftUIIntegration() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["Service"])]
        let output = Emitter.emit(apps: apps, testApps: [], modules: modules)

        XCTAssertTrue(output.contains("@propertyWrapper"))
        XCTAssertTrue(output.contains("struct Inject<Value: Sendable>: DynamicProperty"))
        // Generated env key
        XCTAssertTrue(output.contains("__Katana_App_SnapshotKey"))
        XCTAssertTrue(output.contains("var appSnapshot: App.Snapshot?"))
        XCTAssertTrue(output.contains("func installApp(_ snapshot: App.Snapshot)"))
    }

    func testRespectsAccessLevelOnApp() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["Service"], accessLevel: "public")]
        let output = Emitter.emit(apps: apps, testApps: [], modules: modules)

        XCTAssertTrue(output.contains("public convenience init"))
        XCTAssertTrue(output.contains("public func resolve(_: Logger.Type)"))
    }

    func testPropagatesAvailability() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["Service"], availability: "@available(macOS 14, *)")]
        let output = Emitter.emit(apps: apps, testApps: [], modules: modules)

        XCTAssertTrue(output.contains("@available(macOS 14, *)\nextension App"))
    }

    // MARK: - Test app emission

    func testEmitsTestAppWithOverrideMethods() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["Service"])]
        let testApps = [TestAppDecl(name: "TestApp", productionApp: "App")]
        let output = Emitter.emit(apps: apps, testApps: testApps, modules: modules)

        XCTAssertTrue(output.contains("extension TestApp"))
        XCTAssertTrue(output.contains("func override<T: Injectable & Sendable>(_ type: T.Type, with instance: T) async"))
        XCTAssertTrue(output.contains("extension TestApp: TestContainerMarker"))
    }

    func testEmitsErrorForUnknownProductionApp() {
        let testApps = [TestAppDecl(name: "TestApp", productionApp: "Missing")]
        let output = Emitter.emit(apps: [], testApps: testApps, modules: [:])
        XCTAssertTrue(output.contains("#error"))
        XCTAssertTrue(output.contains("Missing"))
    }

    // MARK: - Cross-module aggregation

    func testAggregatesTypesAcrossModules() {
        let modules = [
            "A": ModuleDecl(name: "A", types: ["Logger"]),
            "B": ModuleDecl(name: "B", types: ["Network"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["A", "B"])]
        let output = Emitter.emit(apps: apps, testApps: [], modules: modules)

        XCTAssertTrue(output.contains("await inner.register(Logger.self)"))
        XCTAssertTrue(output.contains("await inner.register(Network.self)"))
    }

    func testDeduplicatesAcrossModules() {
        let modules = [
            "A": ModuleDecl(name: "A", types: ["Logger"]),
            "B": ModuleDecl(name: "B", types: ["Logger", "Network"]),
        ]
        let apps = [AppDecl(name: "App", modules: ["A", "B"])]
        let output = Emitter.emit(apps: apps, testApps: [], modules: modules)

        // Logger appears once in the register list, not twice.
        let registerCount = output.components(separatedBy: "await inner.register(Logger.self)").count - 1
        XCTAssertEqual(registerCount, 1)
    }
}
