import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Container(T1.self, T2.self, ...)` — typed dependency-graph macro.
///
/// Emits, on the annotated class:
///   - `private let __katanaContainer: Container` (storage for the inner actor)
///   - `init(_ customize:) async` that registers every listed type
///   - `resolve(_:)` async overloads — one per registered type, compile-checked
///   - nested `struct Snapshot: Resolver` with stored properties and typed overloads
///   - `snapshot() async -> Snapshot`
///   - nested `@propertyWrapper struct Inject<Value>` (SwiftUI-gated)
///
/// `@<ClassName>.Inject` reads from the shared `\.katanaResolver` environment
/// key and downcasts to the typed `Snapshot`. The typed `resolve(_:)`
/// overloads on the nested `Snapshot` provide compile-time safety. For
/// multi-container apps, see Documentation/multi-container.md for the
/// per-graph env-key pattern.
public struct ContainerMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ContainerMessage.notAClass))
            return []
        }

        let className = classDecl.name.text
        let typeNames = parseTypes(from: node)
        if typeNames.isEmpty {
            context.diagnose(Diagnostic(node: Syntax(node), message: ContainerMessage.emptyTypeList))
            return []
        }

        // private let __katanaContainer: Container
        let storage: DeclSyntax = "private let __katanaContainer: Container"

        // init(_ customize:) async — registers every type
        let registerLines = typeNames.map { "await inner.register(\($0).self)" }
        let initDecl: DeclSyntax = """
            public init(_ customize: (@Sendable (Container) async -> Void)? = nil) async {
                let inner = Container()
                \(raw: registerLines.joined(separator: "\n    "))
                self.__katanaContainer = inner
                await customize?(inner)
            }
            """

        // Typed resolve overloads — compile-time safety on the container itself
        let resolveOverloads: [DeclSyntax] = typeNames.map { typeName in
            """
            public func resolve(_: \(raw: typeName).Type) async -> \(raw: typeName) {
                await __katanaContainer.resolve(\(raw: typeName).self)
            }
            """
        }

        // Snapshot struct (sync, typed, Resolver-conforming)
        let snapshotDecl = makeSnapshotDecl(className: className, typeNames: typeNames)

        // snapshot() method
        let snapshotLines = typeNames.map { typeName in
            "let \(propertyName(for: typeName)) = await __katanaContainer.resolve(\(typeName).self)"
        }
        let snapshotInitArgs = typeNames.map { typeName in
            let p = propertyName(for: typeName)
            return "\(p): \(p)"
        }
        let snapshotMethod: DeclSyntax = """
            public func snapshot() async -> Snapshot {
                \(raw: snapshotLines.joined(separator: "\n    "))
                return Snapshot(\(raw: snapshotInitArgs.joined(separator: ", ")))
            }
            """

        // SwiftUI Inject — reads the shared katanaResolver env key, downcasts
        // to the typed Snapshot. The host file must `import SwiftUI` for this
        // to compile; on platforms without SwiftUI the #if guard skips it.
        let injectDecl: DeclSyntax = """
            #if canImport(SwiftUI)
            @propertyWrapper
            public struct Inject<Value: Sendable>: DynamicProperty {
                @Environment(\\.katanaResolver) private var resolver
                public init() {}
                public var wrappedValue: Value {
                    guard let snapshot = resolver as? Snapshot else {
                        preconditionFailure(
                            "@\(raw: className).Inject expected \(raw: className).Snapshot in the environment but found \\(type(of: resolver)). Install via `.katana(await \(raw: className)().snapshot())`."
                        )
                    }
                    return snapshot.resolve(Value.self)
                }
            }
            #endif
            """

        return [storage, initDecl] + resolveOverloads + [snapshotDecl, snapshotMethod, injectDecl]
    }

    // MARK: - Helpers

    private static func parseTypes(from node: AttributeSyntax) -> [String] {
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

    private static func propertyName(for typeName: String) -> String {
        guard let first = typeName.first else { return typeName }
        return first.lowercased() + typeName.dropFirst()
    }

    private static func makeSnapshotDecl(className: String, typeNames: [String]) -> DeclSyntax {
        // Direct string construction — multi-line template interpolation
        // smears literal whitespace inconsistently when sub-lists are joined
        // with `\n<spaces>`, producing visually broken output. Building the
        // string by hand gives stable, deterministic indentation.
        var body = "public struct Snapshot: Resolver {\n"
        for type in typeNames {
            body += "    public let \(propertyName(for: type)): \(type)\n"
        }
        body += "\n    public init("
        body += typeNames.map { "\(propertyName(for: $0)): \($0)" }.joined(separator: ", ")
        body += ") {\n"
        for type in typeNames {
            let p = propertyName(for: type)
            body += "        self.\(p) = \(p)\n"
        }
        body += "    }\n\n"
        for type in typeNames {
            body += "    public func resolve(_: \(type).Type) -> \(type) { \(propertyName(for: type)) }\n"
        }
        body += "\n    public func resolve<T: Sendable>(_ type: T.Type) -> T {\n"
        body += "        switch ObjectIdentifier(type) {\n"
        for type in typeNames {
            body += "        case ObjectIdentifier(\(type).self):\n"
            body += "            return \(propertyName(for: type)) as! T\n"
        }
        body += "        default:\n"
        body += "            preconditionFailure(\"\\(type) is not in \(className).Snapshot. Add it to @Container(...).\")\n"
        body += "        }\n"
        body += "    }\n"
        body += "}"
        return DeclSyntax(stringLiteral: body)
    }
}

// MARK: - Diagnostics

enum ContainerMessage: String, DiagnosticMessage {
    case notAClass
    case emptyTypeList

    var message: String {
        switch self {
        case .notAClass:
            return "@Container can only be applied to a class. Use a class declaration."
        case .emptyTypeList:
            return "@Container requires at least one type to register, e.g. @Container(Logger.self)."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Katana", id: "Container.\(rawValue)")
    }

    var severity: DiagnosticSeverity { .error }
}
