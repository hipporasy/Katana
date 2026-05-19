import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InjectableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        if declaration.is(ProtocolDeclSyntax.self) {
            context.diagnose(Diagnostic(node: Syntax(node), message: InjectableMessage.protocolTarget))
            return []
        }
        if declaration.is(EnumDeclSyntax.self) {
            context.diagnose(Diagnostic(node: Syntax(node), message: InjectableMessage.enumTarget))
            return []
        }
        if declaration.is(ExtensionDeclSyntax.self) {
            context.diagnose(Diagnostic(node: Syntax(node), message: InjectableMessage.extensionTarget))
            return []
        }

        let allInits = declaration.memberBlock.members.compactMap {
            $0.decl.as(InitializerDeclSyntax.self)
        }
        let designated = allInits.filter { decl in
            !decl.modifiers.contains { $0.name.text == "convenience" }
        }
        if designated.count > 1 {
            context.diagnose(Diagnostic(node: Syntax(node), message: InjectableMessage.multipleInits))
        }
        let chosenInit = designated.first ?? allInits.first

        let parameters = chosenInit?.signature.parameterClause.parameters ?? []
        for param in parameters {
            if param.ellipsis != nil {
                context.diagnose(Diagnostic(node: Syntax(param), message: InjectableMessage.variadicParam))
                return []
            }
            if let attrs = param.type.as(AttributedTypeSyntax.self),
               attrs.specifiers.contains(where: { $0.trimmedDescription == "inout" }) {
                context.diagnose(Diagnostic(node: Syntax(param), message: InjectableMessage.inoutParam))
                return []
            }
        }

        let scope = readScope(from: node)

        let body: String
        if parameters.isEmpty {
            body = "Self()"
        } else {
            let pieces: [String] = parameters.map { param in
                let label = param.firstName.text
                let typeText = param.type.trimmedDescription
                if label == "_" {
                    return "container.resolve(\(typeText).self)"
                }
                return "\(label): container.resolve(\(typeText).self)"
            }
            body = "await Self(\(pieces.joined(separator: ", ")))"
        }

        let resolveDecl: DeclSyntax = """
            nonisolated static func resolve(from container: Container) async -> sending Self {
                \(raw: body)
            }
            """

        let ext: ExtensionDeclSyntax
        if scope == .transient {
            let scopeDecl: DeclSyntax = "nonisolated static var scope: Scope { .transient }"
            ext = try ExtensionDeclSyntax("extension \(type.trimmed): Injectable") {
                scopeDecl
                resolveDecl
            }
        } else {
            ext = try ExtensionDeclSyntax("extension \(type.trimmed): Injectable") {
                resolveDecl
            }
        }
        return [ext]
    }
}

private func readScope(from node: AttributeSyntax) -> InjectableScope {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
        return .singleton
    }
    for arg in arguments where arg.label?.text == "scope" {
        let text = arg.expression.trimmedDescription
        if text.contains("transient") { return .transient }
        return .singleton
    }
    return .singleton
}

private enum InjectableScope {
    case singleton
    case transient
}

private enum InjectableMessage: String, DiagnosticMessage {
    case protocolTarget
    case enumTarget
    case extensionTarget
    case multipleInits
    case variadicParam
    case inoutParam

    var message: String {
        switch self {
        case .protocolTarget:
            return "@Injectable cannot be applied to protocols"
        case .enumTarget:
            return "@Injectable cannot be applied to enums"
        case .extensionTarget:
            return "@Injectable cannot be applied to extensions"
        case .multipleInits:
            return "@Injectable type has multiple designated initializers; the first will be used. Remove or mark the others 'convenience' to silence this warning."
        case .variadicParam:
            return "@Injectable does not support variadic init parameters"
        case .inoutParam:
            return "@Injectable does not support inout init parameters"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Katana", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .multipleInits: return .warning
        default: return .error
        }
    }
}

@main
struct KatanaPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        InjectableMacro.self,
    ]
}
