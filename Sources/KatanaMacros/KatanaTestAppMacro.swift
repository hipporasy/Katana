import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@KatanaTestApp(of: App.self)` — marker attribute consumed by the
/// `KatanaCodegen` SwiftPM build plugin to generate a test peer of a
/// `@KatanaApp`-built graph. The plugin reads the production app's module list
/// and emits an extension on the annotated class with the same shape
/// `@TestContainer` produces, plus post-construction `override(_:with:)` and
/// `TestContainerMarker` conformance.
///
/// The macro itself emits nothing — see `KatanaAppMacro` for the rationale.
public struct KatanaTestAppMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: KatanaTestAppMessage.notAClass))
            return []
        }

        // Validate `of:` argument is `<App>.self`.
        guard let args = node.arguments?.as(LabeledExprListSyntax.self),
              let ofArg = args.first(where: { $0.label?.text == "of" }),
              ofArg.expression.is(MemberAccessExprSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: KatanaTestAppMessage.missingOf))
            return []
        }
        _ = ofArg
        // Same storage seam as @KatanaApp — see comment there.
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

enum KatanaTestAppMessage: String, DiagnosticMessage {
    case notAClass
    case missingOf

    var message: String {
        switch self {
        case .notAClass:
            return "@KatanaTestApp can only be applied to a class."
        case .missingOf:
            return "@KatanaTestApp requires an `of:` argument referencing the production `@KatanaApp` class, e.g. @KatanaTestApp(of: App.self)."
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "Katana", id: "KatanaTestApp.\(rawValue)") }
    var severity: DiagnosticSeverity { .error }
}
