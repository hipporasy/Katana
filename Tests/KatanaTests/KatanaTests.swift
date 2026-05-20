import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import KatanaMacros

nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Injectable": InjectableMacro.self,
    "Container": ContainerMacro.self,
    "TestContainer": TestContainerMacro.self,
]

final class InjectableMacroTests: XCTestCase {
    func testEmptyInit() {
        assertMacroExpansion(
            """
            @Injectable
            final class Logger {
                init() {}
            }
            """,
            expandedSource: """
            final class Logger {
                init() {}
            }

            extension Logger: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    Self()
                }
            }
            """,
            macros: testMacros
        )
    }

    func testSingleDependency() {
        assertMacroExpansion(
            """
            @Injectable
            final class API {
                init(logger: Logger) {}
            }
            """,
            expandedSource: """
            final class API {
                init(logger: Logger) {}
            }

            extension API: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(logger: container.resolve(Logger.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testMultipleDependencies() {
        assertMacroExpansion(
            """
            @Injectable
            final class AuthService {
                init(network: NetworkService, logger: LoggerService) {}
            }
            """,
            expandedSource: """
            final class AuthService {
                init(network: NetworkService, logger: LoggerService) {}
            }

            extension AuthService: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(network: container.resolve(NetworkService.self), logger: container.resolve(LoggerService.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testTransientScope() {
        assertMacroExpansion(
            """
            @Injectable(scope: .transient)
            final class RequestContext {
                init() {}
            }
            """,
            expandedSource: """
            final class RequestContext {
                init() {}
            }

            extension RequestContext: Injectable {
                nonisolated static var scope: Scope {
                    .transient
                }
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    Self()
                }
            }
            """,
            macros: testMacros
        )
    }

    func testExplicitSingletonScope() {
        assertMacroExpansion(
            """
            @Injectable(scope: .singleton)
            final class Logger {
                init() {}
            }
            """,
            expandedSource: """
            final class Logger {
                init() {}
            }

            extension Logger: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    Self()
                }
            }
            """,
            macros: testMacros
        )
    }

    func testStructTarget() {
        assertMacroExpansion(
            """
            @Injectable
            struct Config {
                init(host: Host) {}
            }
            """,
            expandedSource: """
            struct Config {
                init(host: Host) {}
            }

            extension Config: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(host: container.resolve(Host.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testConvenienceInitIgnored() {
        assertMacroExpansion(
            """
            @Injectable
            final class Service {
                init(client: Client) {}
                convenience init() { self.init(client: Client()) }
            }
            """,
            expandedSource: """
            final class Service {
                init(client: Client) {}
                convenience init() { self.init(client: Client()) }
            }

            extension Service: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(client: container.resolve(Client.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testProtocolTargetDiagnostic() {
        assertMacroExpansion(
            """
            @Injectable
            protocol Service {}
            """,
            expandedSource: """
            protocol Service {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Injectable cannot be applied to protocols",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testEnumTargetDiagnostic() {
        assertMacroExpansion(
            """
            @Injectable
            enum Mode {}
            """,
            expandedSource: """
            enum Mode {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Injectable cannot be applied to enums",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testUnlabeledParam() {
        assertMacroExpansion(
            """
            @Injectable
            final class Wrapper {
                init(_ inner: Inner) {}
            }
            """,
            expandedSource: """
            final class Wrapper {
                init(_ inner: Inner) {}
            }

            extension Wrapper: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(container.resolve(Inner.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testMixedLabels() {
        assertMacroExpansion(
            """
            @Injectable
            final class Mixed {
                init(_ first: A, named: B) {}
            }
            """,
            expandedSource: """
            final class Mixed {
                init(_ first: A, named: B) {}
            }

            extension Mixed: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(container.resolve(A.self), named: container.resolve(B.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testActorTarget() {
        assertMacroExpansion(
            """
            @Injectable
            actor Repository {
                init(client: Client) {}
            }
            """,
            expandedSource: """
            actor Repository {
                init(client: Client) {}
            }

            extension Repository: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(client: container.resolve(Client.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testGenericParamType() {
        assertMacroExpansion(
            """
            @Injectable
            final class UserFeature {
                init(store: Store<User>) {}
            }
            """,
            expandedSource: """
            final class UserFeature {
                init(store: Store<User>) {}
            }

            extension UserFeature: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(store: container.resolve(Store<User>.self))
                }
            }
            """,
            macros: testMacros
        )
    }

    func testMultipleInitsWarning() {
        assertMacroExpansion(
            """
            @Injectable
            final class Service {
                init(client: Client) {}
                init(client: Client, logger: Logger) {}
            }
            """,
            expandedSource: """
            final class Service {
                init(client: Client) {}
                init(client: Client, logger: Logger) {}
            }

            extension Service: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(client: container.resolve(Client.self))
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Injectable type has multiple designated initializers; the first will be used. Remove or mark the others 'convenience' to silence this warning.",
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    func testVariadicParamDiagnostic() {
        assertMacroExpansion(
            """
            @Injectable
            final class Bad {
                init(values: Int...) {}
            }
            """,
            expandedSource: """
            final class Bad {
                init(values: Int...) {}
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Injectable does not support variadic init parameters",
                    line: 3,
                    column: 10
                )
            ],
            macros: testMacros
        )
    }

    func testInoutParamDiagnostic() {
        assertMacroExpansion(
            """
            @Injectable
            final class Bad {
                init(state: inout State) {}
            }
            """,
            expandedSource: """
            final class Bad {
                init(state: inout State) {}
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Injectable does not support inout init parameters",
                    line: 3,
                    column: 10
                )
            ],
            macros: testMacros
        )
    }

    func testInitWithDefaultValue() {
        // Default values are ignored — the container resolves the type regardless.
        assertMacroExpansion(
            """
            @Injectable
            final class Service {
                init(logger: Logger = .shared) {}
            }
            """,
            expandedSource: """
            final class Service {
                init(logger: Logger = .shared) {}
            }

            extension Service: Injectable {
                nonisolated static func resolve(from container: Container) async -> sending Self {
                    await Self(logger: container.resolve(Logger.self))
                }
            }
            """,
            macros: testMacros
        )
    }
}

// MARK: - @Container macro tests

final class ContainerMacroTests: XCTestCase {

    func testEmptyTypeListDiagnoses() {
        assertMacroExpansion(
            """
            @Container
            final class App {}
            """,
            expandedSource: """
            final class App {}
            """,
            diagnostics: [
                .init(
                    message: "@Container requires at least one type to register, e.g. @Container(Logger.self).",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testNotAClassDiagnoses() {
        assertMacroExpansion(
            """
            @Container(Logger.self)
            struct App {}
            """,
            expandedSource: """
            struct App {}
            """,
            diagnostics: [
                .init(
                    message: "@Container can only be applied to a class. Use a class declaration.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testSingleTypeEmitsResolveOverloadAndSnapshot() {
        assertMacroExpansion(
            """
            @Container(Logger.self)
            final class App {}
            """,
            expandedSource: """
            final class App {

                private let __katanaContainer: Container

                public init(_ customize: (@Sendable (Container) async -> Void)? = nil) async {
                    let inner = Container()
                    await inner.register(Logger.self)
                    self.__katanaContainer = inner
                    await customize?(inner)
                }

                public func resolve(_: Logger.Type) async -> Logger {
                    await __katanaContainer.resolve(Logger.self)
                }

                public struct Snapshot: Resolver {
                    public let logger: Logger

                    public init(logger: Logger) {
                        self.logger = logger
                    }

                    public func resolve(_: Logger.Type) -> Logger {
                        logger
                    }

                    public func resolve<T: Sendable>(_ type: T.Type) -> T {
                        switch ObjectIdentifier(type) {
                        case ObjectIdentifier(Logger.self):
                            return logger as! T
                        default:
                            preconditionFailure("\\(type) is not in App.Snapshot. Add it to @Container(...).")
                        }
                    }
                }

                public func snapshot() async -> Snapshot {
                    let logger = await __katanaContainer.resolve(Logger.self)
                    return Snapshot(logger: logger)
                }

                #if canImport(SwiftUI)
                @propertyWrapper
                public struct Inject<Value: Sendable>: DynamicProperty {
                    @Environment(\\.katanaResolver) private var resolver
                    public init() {
                    }
                    public var wrappedValue: Value {
                        guard let snapshot = resolver as? Snapshot else {
                            preconditionFailure(
                                "@App.Inject expected App.Snapshot in the environment but found \\(type(of: resolver)). Install via `.katana(await App().snapshot())`."
                            )
                        }
                        return snapshot.resolve(Value.self)
                    }
                }
                #endif
            }
            """,
            macros: testMacros
        )
    }

    func testEmitsOverridePostConstructionAndMarker() {
        // @TestContainer adds two override methods on top of @Container's
        // emission, plus a TestContainerMarker conformance via extension.
        // This test pins the additive bits; the Container expansion shape is
        // covered by testSingleTypeEmitsResolveOverloadAndSnapshot.
        assertMacroExpansion(
            """
            @TestContainer(Logger.self)
            final class TestApp {}
            """,
            expandedSource: """
            final class TestApp {

                private let __katanaContainer: Container

                public init(_ customize: (@Sendable (Container) async -> Void)? = nil) async {
                    let inner = Container()
                    await inner.register(Logger.self)
                    self.__katanaContainer = inner
                    await customize?(inner)
                }

                public func resolve(_: Logger.Type) async -> Logger {
                    await __katanaContainer.resolve(Logger.self)
                }

                public struct Snapshot: Resolver {
                    public let logger: Logger

                    public init(logger: Logger) {
                        self.logger = logger
                    }

                    public func resolve(_: Logger.Type) -> Logger {
                        logger
                    }

                    public func resolve<T: Sendable>(_ type: T.Type) -> T {
                        switch ObjectIdentifier(type) {
                        case ObjectIdentifier(Logger.self):
                            return logger as! T
                        default:
                            preconditionFailure("\\(type) is not in TestApp.Snapshot. Add it to @Container(...).")
                        }
                    }
                }

                public func snapshot() async -> Snapshot {
                    let logger = await __katanaContainer.resolve(Logger.self)
                    return Snapshot(logger: logger)
                }

                #if canImport(SwiftUI)
                @propertyWrapper
                public struct Inject<Value: Sendable>: DynamicProperty {
                    @Environment(\\.katanaResolver) private var resolver
                    public init() {
                    }
                    public var wrappedValue: Value {
                        guard let snapshot = resolver as? Snapshot else {
                            preconditionFailure(
                                "@TestApp.Inject expected TestApp.Snapshot in the environment but found \\(type(of: resolver)). Install via `.katana(await TestApp().snapshot())`."
                            )
                        }
                        return snapshot.resolve(Value.self)
                    }
                }
                #endif

                /// Replaces a registered type with an instance after construction.
                /// Clears any cached singleton so the next resolve uses the new value.
                public func override<T: Injectable & Sendable>(_ type: T.Type, with instance: T) async {
                    await __katanaContainer.override(type, with: instance)
                }

                /// Replaces a registered type with a factory after construction.
                /// Clears any cached singleton so the next resolve uses the new factory.
                public func override<T: Injectable & Sendable>(
                    _ type: T.Type,
                    factory: @escaping @Sendable (Container) async -> T
                ) async {
                    await __katanaContainer.override(type, factory: factory)
                }
            }

            extension TestApp: TestContainerMarker {
            }
            """,
            macros: testMacros
        )
    }
}

// MARK: - @Container two-type expansion (separate suite, kept short)

final class ContainerMacroTwoTypeTests: XCTestCase {
    func testTwoTypesEmitOverloadsForBoth() {
        assertMacroExpansion(
            """
            @Container(Logger.self, Network.self)
            final class App {}
            """,
            expandedSource: """
            final class App {

                private let __katanaContainer: Container

                public init(_ customize: (@Sendable (Container) async -> Void)? = nil) async {
                    let inner = Container()
                    await inner.register(Logger.self)
                    await inner.register(Network.self)
                    self.__katanaContainer = inner
                    await customize?(inner)
                }

                public func resolve(_: Logger.Type) async -> Logger {
                    await __katanaContainer.resolve(Logger.self)
                }

                public func resolve(_: Network.Type) async -> Network {
                    await __katanaContainer.resolve(Network.self)
                }

                public struct Snapshot: Resolver {
                    public let logger: Logger
                    public let network: Network

                    public init(logger: Logger, network: Network) {
                        self.logger = logger
                        self.network = network
                    }

                    public func resolve(_: Logger.Type) -> Logger {
                        logger
                    }
                    public func resolve(_: Network.Type) -> Network {
                        network
                    }

                    public func resolve<T: Sendable>(_ type: T.Type) -> T {
                        switch ObjectIdentifier(type) {
                        case ObjectIdentifier(Logger.self):
                            return logger as! T
                    case ObjectIdentifier(Network.self):
                            return network as! T
                        default:
                            preconditionFailure("\\(type) is not in App.Snapshot. Add it to @Container(...).")
                        }
                    }
                }

                public func snapshot() async -> Snapshot {
                    let logger = await __katanaContainer.resolve(Logger.self)
                    let network = await __katanaContainer.resolve(Network.self)
                    return Snapshot(logger: logger, network: network)
                }

                #if canImport(SwiftUI)
                @propertyWrapper
                public struct Inject<Value: Sendable>: DynamicProperty {
                    @Environment(\\.katanaResolver) private var resolver
                    public init() {
                    }
                    public var wrappedValue: Value {
                        guard let snapshot = resolver as? Snapshot else {
                            preconditionFailure(
                                "@App.Inject expected App.Snapshot in the environment but found \\(type(of: resolver)). Install via `.katana(await App().snapshot())`."
                            )
                        }
                        return snapshot.resolve(Value.self)
                    }
                }
                #endif
            }
            """,
            macros: testMacros
        )
    }
}
