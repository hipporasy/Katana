import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Module(T1.self, T2.self, ...)` — groups injectable types so they can be
/// referenced as a unit from `@Container(modules: [...])`. The macro also
/// emits a `static let types` array that you can read at runtime for
/// documentation, debugging, or hand-rolled aggregation.
///
/// Emits:
///   - `static let types: [any (Injectable & Sendable).Type] = [...]`
///   - `extension <Enum>: KatanaModule {}`
public struct ModuleMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ModuleMessage.notAnEnum))
            return []
        }

        let typeNames = parseTypes(from: node)
        if typeNames.isEmpty {
            context.diagnose(Diagnostic(node: Syntax(node), message: ModuleMessage.emptyTypeList))
            return []
        }

        let typeList = typeNames.map { "\($0).self" }.joined(separator: ",\n        ")
        let typesDecl: DeclSyntax = """
            public static let types: [any (Injectable & Sendable).Type] = [
                \(raw: typeList)
            ]
            """
        return [typesDecl]
    }

    // MARK: - ExtensionMacro (KatanaModule conformance)

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(EnumDeclSyntax.self) else { return [] }
        let ext = try ExtensionDeclSyntax("extension \(type.trimmed): KatanaModule {}")
        return [ext]
    }

    // MARK: - Helpers

    static func parseTypes(from node: AttributeSyntax) -> [String] {
        guard let args = node.arguments?.as(LabeledExprListSyntax.self) else { return [] }
        return args.compactMap { arg -> String? in
            guard let memberAccess = arg.expression.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "self",
                  let base = memberAccess.base else {
                return nil
            }
            return base.trimmedDescription
        }
    }
}

// MARK: - Diagnostics

enum ModuleMessage: String, DiagnosticMessage {
    case notAnEnum
    case emptyTypeList

    var message: String {
        switch self {
        case .notAnEnum:
            return "@Module can only be applied to an enum. Use a case-less enum for module grouping."
        case .emptyTypeList:
            return "@Module requires at least one type, e.g. @Module(Logger.self)."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Katana", id: "Module.\(rawValue)")
    }

    var severity: DiagnosticSeverity { .error }
}
