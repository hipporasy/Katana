import XCTest
@testable import KatanaCodegenCore

final class EmitterTests: XCTestCase {

    // MARK: - Container emission

    func testEmitsResolveOverloadPerType() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger", "Network"]),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["Service"])]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("func resolve(_: Logger.Type) async -> Logger"))
        XCTAssertTrue(output.contains("func resolve(_: Network.Type) async -> Network"))
        XCTAssertTrue(output.contains("await inner.register(Logger.self)"))
        XCTAssertTrue(output.contains("await inner.register(Network.self)"))
    }

    func testEmitsTypedSnapshotStruct() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["Service"])]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("struct Snapshot: Resolver"))
        XCTAssertTrue(output.contains("let logger: Logger"))
        XCTAssertTrue(output.contains("func resolve(_: Logger.Type) -> Logger { logger }"))
        XCTAssertTrue(output.contains("ObjectIdentifier(Logger.self)"))
    }

    func testEmitsSwiftUIIntegration() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["Service"])]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("__Katana_App_SnapshotKey"))
        XCTAssertTrue(output.contains("var katanaDefault: (any Resolver)?"))
        XCTAssertTrue(output.contains("func katana(_ snapshot: App.Snapshot)"))
    }

    func testRespectsAccessLevelOnContainer() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["Service"], accessLevel: "public")]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("public convenience init"))
        XCTAssertTrue(output.contains("public func resolve(_: Logger.Type)"))
    }

    func testPropagatesAvailability() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let containers = [
            ContainerDecl(name: "App", modules: ["Service"], availability: "@available(macOS 14, *)"),
        ]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("@available(macOS 14, *)\nextension App"))
    }

    // MARK: - Test container emission

    func testEmitsTestContainerOverrides() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let containers = [
            ContainerDecl(name: "TestApp", modules: ["Service"], isTest: true),
        ]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("extension TestApp"))
        XCTAssertTrue(output.contains("func override<T: Injectable & Sendable>(_ type: T.Type, with instance: T) async"))
        // TestContainerMarker conformance comes from the macro, not the emitter.
        XCTAssertFalse(output.contains("TestContainerMarker"))
    }

    // MARK: - Scope handling

    func testDefaultScopeEmitsBareInjectInit() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"]),
        ]
        let containers = [ContainerDecl(name: "App", scope: "default", modules: ["Service"])]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("extension Inject"))
        XCTAssertTrue(output.contains("self.init(\\.katanaDefault)"))
    }

    func testCustomScopeDoesNotEmitBareInjectInit() {
        let modules = [
            "Checkout": ModuleDecl(name: "Checkout", types: ["CartStore"]),
        ]
        let containers = [ContainerDecl(name: "Checkout", scope: "checkout", modules: ["Checkout"])]
        let output = Emitter.emit(containers: containers, modules: modules)

        // No bare init() — user must write @Inject(\.checkout) explicitly.
        XCTAssertFalse(output.contains("self.init(\\.katanaDefault)"))
        // Env key uses the scope name verbatim.
        XCTAssertTrue(output.contains("var checkout: (any Resolver)?"))
    }

    func testMultipleDefaultContainersSuppressBareInjectInit() {
        let modules = [
            "S": ModuleDecl(name: "S", types: ["Logger"]),
        ]
        let containers = [
            ContainerDecl(name: "App", scope: "default", modules: ["S"]),
            ContainerDecl(name: "Other", scope: "default", modules: ["S"]),
        ]
        // Two .default containers — the validator would block this in practice;
        // the emitter only emits the bare init when *exactly one* is at .default.
        let output = Emitter.emit(containers: containers, modules: modules)
        XCTAssertFalse(output.contains("self.init(\\.katanaDefault)"))
    }

    func testEmitsContainerScopeStaticsFromScopeRegistry() {
        let modules = [
            "S": ModuleDecl(name: "S", types: ["Logger"]),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["S"])]
        let scopes = [ScopeRegistryDecl(name: "AppScope", cases: ["checkout", "payment"])]
        let output = Emitter.emit(containers: containers, scopes: scopes, modules: modules)

        XCTAssertTrue(output.contains("extension ContainerScope"))
        XCTAssertTrue(output.contains("static let checkout = ContainerScope(\"checkout\")"))
        XCTAssertTrue(output.contains("static let payment = ContainerScope(\"payment\")"))
        // The built-in .default is NOT re-emitted even if a registry case is named "default".
        XCTAssertFalse(output.contains("static let default = ContainerScope(\"default\")"))
    }

    // MARK: - Cross-module aggregation

    func testAggregatesTypesAcrossModules() {
        let modules = [
            "A": ModuleDecl(name: "A", types: ["Logger"]),
            "B": ModuleDecl(name: "B", types: ["Network"]),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["A", "B"])]
        let output = Emitter.emit(containers: containers, modules: modules)

        XCTAssertTrue(output.contains("await inner.register(Logger.self)"))
        XCTAssertTrue(output.contains("await inner.register(Network.self)"))
    }

    func testDeduplicatesAcrossModules() {
        let modules = [
            "A": ModuleDecl(name: "A", types: ["Logger"]),
            "B": ModuleDecl(name: "B", types: ["Logger", "Network"]),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["A", "B"])]
        let output = Emitter.emit(containers: containers, modules: modules)

        let registerCount = output.components(separatedBy: "await inner.register(Logger.self)").count - 1
        XCTAssertEqual(registerCount, 1)
    }
}
