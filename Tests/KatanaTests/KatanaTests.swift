import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import KatanaMacros

nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Injectable": InjectableMacro.self,
    "Container": ContainerMacro.self,
    "TestContainer": TestContainerMacro.self,
    "Module": ModuleMacro.self,
    "Scope": ScopeMacro.self,
]

// MARK: - @Injectable

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
}

// MARK: - @Container

final class ContainerMacroTests: XCTestCase {

    func testEmitsStorageAndDesignatedInit() {
        assertMacroExpansion(
            """
            @Container(modules: [ServiceModule.self])
            final class App {}
            """,
            expandedSource: """
            final class App {

                /// Container storage owned by KatanaCodegen. Do not access directly.
                internal let __katanaContainer: Container

                /// Designated initializer used by the KatanaCodegen-generated
                /// async convenience init. Do not call directly.
                internal init(__katanaContainer container: Container) {
                    self.__katanaContainer = container
                }
            }
            """,
            macros: testMacros
        )
    }

    func testEmitsSameShapeWithCustomScope() {
        // The macro only validates shape — it does not parse the scope value.
        // The plugin reads `scope:` separately.
        assertMacroExpansion(
            """
            @Container(scope: .checkout, modules: [CheckoutModule.self])
            final class Checkout {}
            """,
            expandedSource: """
            final class Checkout {

                /// Container storage owned by KatanaCodegen. Do not access directly.
                internal let __katanaContainer: Container

                /// Designated initializer used by the KatanaCodegen-generated
                /// async convenience init. Do not call directly.
                internal init(__katanaContainer container: Container) {
                    self.__katanaContainer = container
                }
            }
            """,
            macros: testMacros
        )
    }

    func testMissingModulesDiagnoses() {
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
                    message: "@Container requires a `modules:` argument, e.g. @Container(modules: [ServiceModule.self]).",
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
            @Container(modules: [ServiceModule.self])
            struct App {}
            """,
            expandedSource: """
            struct App {}
            """,
            diagnostics: [
                .init(
                    message: "@Container can only be applied to a class.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testModulesNotArrayDiagnoses() {
        assertMacroExpansion(
            """
            @Container(modules: ServiceModule.self)
            final class App {}
            """,
            expandedSource: """
            final class App {}
            """,
            diagnostics: [
                .init(
                    message: "`modules:` must be an array literal of `.self` references, e.g. modules: [ServiceModule.self, RepositoryModule.self].",
                    line: 1,
                    column: 21
                )
            ],
            macros: testMacros
        )
    }
}

// MARK: - @TestContainer

final class TestContainerMacroTests: XCTestCase {

    func testEmitsStorageAndMarker() {
        assertMacroExpansion(
            """
            @TestContainer(modules: [ServiceModule.self])
            final class TestApp {}
            """,
            expandedSource: """
            final class TestApp {

                /// Container storage owned by KatanaCodegen. Do not access directly.
                internal let __katanaContainer: Container

                /// Designated initializer used by the KatanaCodegen-generated
                /// async convenience init. Do not call directly.
                internal init(__katanaContainer container: Container) {
                    self.__katanaContainer = container
                }
            }

            extension TestApp: TestContainerMarker {
            }
            """,
            macros: testMacros
        )
    }
}

// MARK: - @Module

final class ModuleMacroTests: XCTestCase {

    func testEmitsTypesAndConformance() {
        assertMacroExpansion(
            """
            @Module(Logger.self, NetworkClient.self)
            enum ServiceModule {}
            """,
            expandedSource: """
            enum ServiceModule {

                public static let types: [any (Injectable & Sendable).Type] = [
                    Logger.self,
                        NetworkClient.self
                ]
            }

            extension ServiceModule: KatanaModule {
            }
            """,
            macros: testMacros
        )
    }

    func testEmptyTypeListDiagnoses() {
        assertMacroExpansion(
            """
            @Module
            enum EmptyModule {}
            """,
            expandedSource: """
            enum EmptyModule {}

            extension EmptyModule: KatanaModule {
            }
            """,
            diagnostics: [
                .init(
                    message: "@Module requires at least one type, e.g. @Module(Logger.self).",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testAppliedToClassDiagnoses() {
        assertMacroExpansion(
            """
            @Module(Logger.self)
            final class WrongTarget {}
            """,
            expandedSource: """
            final class WrongTarget {}
            """,
            diagnostics: [
                .init(
                    message: "@Module can only be applied to an enum. Use a case-less enum for module grouping.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }
}

// MARK: - @Scope

final class ScopeMacroTests: XCTestCase {

    func testEmitsKatanaScopeConformance() {
        assertMacroExpansion(
            """
            @Scope
            enum AppScope {
                case checkout
                case payment
            }
            """,
            expandedSource: """
            enum AppScope {
                case checkout
                case payment
            }

            extension AppScope: KatanaScope {
            }
            """,
            macros: testMacros
        )
    }

    func testEmptyEnumIsValid() {
        // The plugin emits the ContainerScope statics from collected cases;
        // an empty enum just contributes nothing.
        assertMacroExpansion(
            """
            @Scope
            enum AppScope {}
            """,
            expandedSource: """
            enum AppScope {}

            extension AppScope: KatanaScope {
            }
            """,
            macros: testMacros
        )
    }

    func testNotAnEnumDiagnoses() {
        assertMacroExpansion(
            """
            @Scope
            struct AppScope {}
            """,
            expandedSource: """
            struct AppScope {}
            """,
            diagnostics: [
                .init(
                    message: "@Scope can only be applied to an enum.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testAssociatedValueDiagnoses() {
        assertMacroExpansion(
            """
            @Scope
            enum AppScope {
                case checkout(String)
            }
            """,
            expandedSource: """
            enum AppScope {
                case checkout(String)
            }

            extension AppScope: KatanaScope {
            }
            """,
            diagnostics: [
                .init(
                    message: "@Scope cases cannot have associated values. Scopes are flat names.",
                    line: 3,
                    column: 10
                )
            ],
            macros: testMacros
        )
    }
}
