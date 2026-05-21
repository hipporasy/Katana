import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@KatanaApp(modules: [...])` — marker attribute consumed by the
/// `KatanaCodegen` SwiftPM build plugin. The plugin scans the target's source
/// files, aggregates the type lists from referenced `@Module`s, and emits a
/// generated extension on the annotated class with the same shape `@Container`
/// produces from an inline type list.
///
/// The macro itself emits nothing — its job is to make the attribute
/// syntactically valid and validate basic argument shape. Real codegen happens
/// in the build plugin (see `Documentation/modules.md`).
///
/// **Without the `KatanaCodegen` plugin installed in your `Package.swift`,
/// `@KatanaApp` produces an empty class.** Call sites that expect `resolve(_:)`,
/// `snapshot()`, etc. will fail to compile, surfacing the missing plugin.
public struct KatanaAppMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: KatanaAppMessage.notAClass))
            return []
        }

        // Validate `modules:` argument shape — must be an array literal of `.self` references.
        if let args = node.arguments?.as(LabeledExprListSyntax.self) {
            for arg in args where arg.label?.text == "modules" {
                guard arg.expression.is(ArrayExprSyntax.self) else {
                    context.diagnose(Diagnostic(node: Syntax(arg.expression), message: KatanaAppMessage.modulesNotArray))
                    return []
                }
            }
        }

        // Emit the storage + a designated init taking the inner Container.
        // Why both:
        //   - Swift extensions cannot add stored properties, so the storage
        //     must live on the class itself.
        //   - We need to suppress the synthesised `init()` so the call site
        //     `await App()` unambiguously routes to the plugin-generated
        //     async convenience init (otherwise the sync default wins).
        // The designated init is `internal` — callable from the plugin's
        // generated extension in the same module, not exposed publicly.
        let storage: DeclSyntax = """
            /// Container storage owned by KatanaCodegen. Do not access directly.
            internal let __katanaContainer: Container
            """
        let designated: DeclSyntax = """
            /// Designated initializer used by the KatanaCodegen-generated
            /// async convenience init. Do not call directly.
            internal init(__katanaContainer container: Container) {
                self.__katanaContainer = container
            }
            """
        return [storage, designated]
    }
}

enum KatanaAppMessage: String, DiagnosticMessage {
    case notAClass
    case modulesNotArray

    var message: String {
        switch self {
        case .notAClass:
            return "@KatanaApp can only be applied to a class."
        case .modulesNotArray:
            return "`modules:` must be an array literal of `.self` references, e.g. modules: [RepositoryModule.self, ServiceModule.self]."
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "Katana", id: "KatanaApp.\(rawValue)") }
    var severity: DiagnosticSeverity { .error }
}
