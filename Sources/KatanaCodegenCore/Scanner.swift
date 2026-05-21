import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Scanner model

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

public struct AppDecl: Equatable {
    public let name: String
    public let modules: [String]
    public let accessLevel: String       // "public" or "" (internal)
    public let availability: String?     // raw @available(...) attribute, if any

    public init(name: String, modules: [String], accessLevel: String = "", availability: String? = nil) {
        self.name = name
        self.modules = modules
        self.accessLevel = accessLevel
        self.availability = availability
    }
}

public struct TestAppDecl: Equatable {
    public let name: String
    public let productionApp: String
    public let accessLevel: String
    public let availability: String?

    public init(name: String, productionApp: String, accessLevel: String = "", availability: String? = nil) {
        self.name = name
        self.productionApp = productionApp
        self.accessLevel = accessLevel
        self.availability = availability
    }
}

// MARK: - Scanner

public final class Scanner {
    public private(set) var modules: [String: ModuleDecl] = [:]
    public private(set) var apps: [AppDecl] = []
    public private(set) var testApps: [TestAppDecl] = []

    public init() {}

    public func scan(source: String, path: String = "") {
        let tree = Parser.parse(source: source)
        let visitor = ScannerVisitor(currentPath: path, viewMode: .sourceAccurate)
        visitor.walk(tree)

        for module in visitor.modules {
            modules[module.name] = module
        }
        apps.append(contentsOf: visitor.apps)
        testApps.append(contentsOf: visitor.testApps)
    }
}

// MARK: - Syntax visitor

private final class ScannerVisitor: SyntaxVisitor {
    let currentPath: String
    var modules: [ModuleDecl] = []
    var apps: [AppDecl] = []
    var testApps: [TestAppDecl] = []

    init(currentPath: String, viewMode: SyntaxTreeViewMode) {
        self.currentPath = currentPath
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if let attr = node.attributes.firstAttribute(named: "Module") {
            let types = parseTypeListArguments(attr)
            modules.append(ModuleDecl(name: node.name.text, types: types, path: currentPath))
        }
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = accessLevel(of: node.modifiers)
        let availability = availability(of: node.attributes)

        if let attr = node.attributes.firstAttribute(named: "KatanaApp") {
            let mods = parseModulesArgument(attr)
            apps.append(AppDecl(
                name: node.name.text,
                modules: mods,
                accessLevel: access,
                availability: availability
            ))
        } else if let attr = node.attributes.firstAttribute(named: "KatanaTestApp") {
            if let prod = parseOfArgument(attr) {
                testApps.append(TestAppDecl(
                    name: node.name.text,
                    productionApp: prod,
                    accessLevel: access,
                    availability: availability
                ))
            }
        }
        return .skipChildren
    }
}

// MARK: - Attribute parsing helpers

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

/// Reads `(A.self, B.self, C.self)` from an attribute's variadic positional args.
private func parseTypeListArguments(_ attr: AttributeSyntax) -> [String] {
    guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else { return [] }
    return args.compactMap { extractTypeName(from: $0.expression) }
}

/// Reads `modules: [A.self, B.self]` — finds the labeled `modules:` arg and
/// extracts the array contents.
private func parseModulesArgument(_ attr: AttributeSyntax) -> [String] {
    guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else { return [] }
    for arg in args where arg.label?.text == "modules" {
        if let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
            return arrayExpr.elements.compactMap { extractTypeName(from: $0.expression) }
        }
    }
    return []
}

/// Reads `of: App.self` — finds the labeled `of:` arg, returns "App".
private func parseOfArgument(_ attr: AttributeSyntax) -> String? {
    guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in args where arg.label?.text == "of" {
        return extractTypeName(from: arg.expression)
    }
    return nil
}

/// Pulls "Foo" out of an expression like `Foo.self`.
private func extractTypeName(from expr: ExprSyntax) -> String? {
    guard let memberAccess = expr.as(MemberAccessExprSyntax.self),
          memberAccess.declName.baseName.text == "self",
          let base = memberAccess.base else {
        return nil
    }
    return base.trimmedDescription
}

// MARK: - Modifier / attribute helpers

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
