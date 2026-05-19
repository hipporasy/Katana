import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import KatanaMacros

nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Injectable": InjectableMacro.self,
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
