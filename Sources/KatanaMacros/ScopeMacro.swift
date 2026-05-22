import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Scope` — declares a registry of custom container scopes.
///
/// The macro adds the `KatanaScope` marker conformance and diagnoses target
/// shape. The `KatanaCodegen` build plugin emits the `ContainerScope.<case>`
/// statics — peer macros can't introduce arbitrary names at global scope.
public struct ScopeMacro: ExtensionMacro {

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ScopeMessage.notAnEnum))
            return []
        }

        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements where element.parameterClause != nil {
                context.diagnose(Diagnostic(node: Syntax(element), message: ScopeMessage.associatedValue))
            }
        }

        let ext = try ExtensionDeclSyntax("extension \(type.trimmed): KatanaScope {}")
        return [ext]
    }
}

enum ScopeMessage: String, DiagnosticMessage {
    case notAnEnum
    case associatedValue

    var message: String {
        switch self {
        case .notAnEnum:
            return "@Scope can only be applied to an enum."
        case .associatedValue:
            return "@Scope cases cannot have associated values. Scopes are flat names."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Katana", id: "Scope.\(rawValue)")
    }

    var severity: DiagnosticSeverity { .error }
}
