import Foundation
import SwiftParser
import SwiftSyntax

public struct ModuleDecl: Equatable {
    public let name: String
    public let types: [String]
    public let path: String

    public init(name: String, types: [String], path: String = "") {
        self.name = name
        self.types = types
        self.path = path
    }
}

public struct ContainerDecl: Equatable {
    public let name: String
    public let scope: String
    public let modules: [String]
    public let accessLevel: String
    public let availability: String?
    public let isTest: Bool
    public let path: String

    public init(
        name: String,
        scope: String = "default",
        modules: [String],
        accessLevel: String = "",
        availability: String? = nil,
        isTest: Bool = false,
        path: String = ""
    ) {
        self.name = name
        self.scope = scope
        self.modules = modules
        self.accessLevel = accessLevel
        self.availability = availability
        self.isTest = isTest
        self.path = path
    }
}

public struct ScopeRegistryDecl: Equatable {
    public let name: String
    public let cases: [String]
    public let path: String

    public init(name: String, cases: [String], path: String = "") {
        self.name = name
        self.cases = cases
        self.path = path
    }
}

/// An import statement extracted from source. The emitter replays these in
/// the generated file so it can reference the same types user files do —
/// needed for test targets that use `@testable import` to reach internal
/// production types.
public struct ImportDecl: Equatable, Hashable {
    public let moduleName: String
    public let isTestable: Bool

    public init(moduleName: String, isTestable: Bool) {
        self.moduleName = moduleName
        self.isTestable = isTestable
    }
}

public final class Scanner {
    public private(set) var modules: [String: ModuleDecl] = [:]
    public private(set) var containers: [ContainerDecl] = []
    public private(set) var scopes: [ScopeRegistryDecl] = []
    public private(set) var imports: Set<ImportDecl> = []

    public init() {}

    public func scan(source: String, path: String = "") {
        let tree = Parser.parse(source: source)
        let visitor = ScannerVisitor(currentPath: path, viewMode: .sourceAccurate)
        visitor.walk(tree)

        for module in visitor.modules {
            modules[module.name] = module
        }
        containers.append(contentsOf: visitor.containers)
        scopes.append(contentsOf: visitor.scopes)
        for imp in visitor.imports {
            imports.insert(imp)
        }
    }
}

private final class ScannerVisitor: SyntaxVisitor {
    let currentPath: String
    var modules: [ModuleDecl] = []
    var containers: [ContainerDecl] = []
    var scopes: [ScopeRegistryDecl] = []
    var imports: [ImportDecl] = []

    init(currentPath: String, viewMode: SyntaxTreeViewMode) {
        self.currentPath = currentPath
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let modulePath = node.path.map { $0.name.text }.joined(separator: ".")
        // Framework imports are already emitted at the top of the generated file.
        let skipList: Set<String> = ["Foundation", "Katana", "SwiftUI", "SwiftUICore"]
        if skipList.contains(modulePath) { return .skipChildren }

        let isTestable = node.attributes.contains { element in
            guard let attr = element.as(AttributeSyntax.self),
                  let id = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return id.name.text == "testable"
        }
        imports.append(ImportDecl(moduleName: modulePath, isTestable: isTestable))
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if let attr = node.attributes.firstAttribute(named: "Module") {
            let types = parseTypeListArguments(attr)
            modules.append(ModuleDecl(name: node.name.text, types: types, path: currentPath))
        }
        if node.attributes.firstAttribute(named: "Scope") != nil {
            let cases = parseEnumCases(node)
            scopes.append(ScopeRegistryDecl(name: node.name.text, cases: cases, path: currentPath))
        }
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = accessLevel(of: node.modifiers)
        let availability = availability(of: node.attributes)

        if let attr = node.attributes.firstAttribute(named: "Container") {
            containers.append(ContainerDecl(
                name: node.name.text,
                scope: parseScopeArgument(attr) ?? "default",
                modules: parseModulesArgument(attr),
                accessLevel: access,
                availability: availability,
                isTest: false,
                path: currentPath
            ))
        } else if let attr = node.attributes.firstAttribute(named: "TestContainer") {
            containers.append(ContainerDecl(
                name: node.name.text,
                scope: parseScopeArgument(attr) ?? "default",
                modules: parseModulesArgument(attr),
                accessLevel: access,
                availability: availability,
                isTest: true,
                path: currentPath
            ))
        }
        return .skipChildren
    }
}

extension AttributeListSyntax {
    func firstAttribute(named name: String) -> AttributeSyntax? {
        for element in self {
            if let attr = element.as(AttributeSyntax.self),
               let id = attr.attributeName.as(IdentifierTypeSyntax.self),
               id.name.text == name {
                return attr
            }
        }
        return nil
    }
}

private func parseTypeListArguments(_ attr: AttributeSyntax) -> [String] {
    guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else { return [] }
    return args.compactMap { extractTypeName(from: $0.expression) }
}

private func parseModulesArgument(_ attr: AttributeSyntax) -> [String] {
    guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else { return [] }
    for arg in args where arg.label?.text == "modules" {
        if let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
            return arrayExpr.elements.compactMap { extractTypeName(from: $0.expression) }
        }
    }
    return []
}

private func parseScopeArgument(_ attr: AttributeSyntax) -> String? {
    guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in args where arg.label?.text == "scope" {
        if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
    }
    return nil
}

private func extractTypeName(from expr: ExprSyntax) -> String? {
    guard let memberAccess = expr.as(MemberAccessExprSyntax.self),
          memberAccess.declName.baseName.text == "self",
          let base = memberAccess.base else {
        return nil
    }
    return base.trimmedDescription
}

private func parseEnumCases(_ enumDecl: EnumDeclSyntax) -> [String] {
    var names: [String] = []
    for member in enumDecl.memberBlock.members {
        guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
        for element in caseDecl.elements {
            if element.parameterClause != nil { continue }
            names.append(element.name.text)
        }
    }
    return names
}

private func accessLevel(of modifiers: DeclModifierListSyntax) -> String {
    for modifier in modifiers {
        let text = modifier.name.text
        switch text {
        case "public", "open", "internal", "fileprivate", "private":
            return text
        default:
            continue
        }
    }
    return ""
}

private func availability(of attributes: AttributeListSyntax) -> String? {
    for element in attributes {
        guard let attr = element.as(AttributeSyntax.self) else { continue }
        if let id = attr.attributeName.as(IdentifierTypeSyntax.self),
           id.name.text == "available" {
            return attr.trimmedDescription
        }
    }
    return nil
}
