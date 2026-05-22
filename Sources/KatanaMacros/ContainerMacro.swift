import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Container(scope: .X, modules: [...])` — declares a typed dependency-graph
/// class. The macro emits the `__katanaContainer` storage and a designated
/// initializer; everything else (the typed API, env slot, install modifier,
/// bare `@Inject` init) is emitted by the `KatanaCodegen` build plugin.
public struct ContainerMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ContainerMessage.notAClass))
            return []
        }

        guard let args = node.arguments?.as(LabeledExprListSyntax.self),
              let modulesArg = args.first(where: { $0.label?.text == "modules" }) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ContainerMessage.missingModules))
            return []
        }
        guard modulesArg.expression.is(ArrayExprSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(modulesArg.expression), message: ContainerMessage.modulesNotArray))
            return []
        }

        // Storage seam: extensions can't add stored properties, so the storage
        // lives on the class. The designated `init(__katanaContainer:)` keeps
        // `await App()` from resolving to a synthesised sync default — the
        // plugin-emitted async convenience init is the public surface.
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

enum ContainerMessage: String, DiagnosticMessage {
    case notAClass
    case missingModules
    case modulesNotArray

    var message: String {
        switch self {
        case .notAClass:
            return "@Container can only be applied to a class."
        case .missingModules:
            return "@Container requires a `modules:` argument, e.g. @Container(modules: [ServiceModule.self])."
        case .modulesNotArray:
            return "`modules:` must be an array literal of `.self` references, e.g. modules: [ServiceModule.self, RepositoryModule.self]."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Katana", id: "Container.\(rawValue)")
    }

    var severity: DiagnosticSeverity { .error }
}
