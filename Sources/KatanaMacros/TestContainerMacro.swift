import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@TestContainer(T1.self, T2.self, ...)` — typed dependency-graph macro for
/// tests. Emits everything `@Container` does, plus:
///   - `func override(_:with:) async` — post-construction instance override
///   - `func override(_:factory:) async` — post-construction factory override
///   - conformance to `TestContainerMarker` (lint hook for "tests only")
public struct TestContainerMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Reuse @Container's emission for init/resolve/Snapshot/Inject.
        var decls = try ContainerMacro.expansion(
            of: node,
            providingMembersOf: declaration,
            in: context
        )

        guard declaration.is(ClassDeclSyntax.self) else { return decls }

        // Test-only additions: post-construction overrides. These delegate to
        // the inner Container actor — same semantics as Container.override,
        // exposed as methods on the typed test container for ergonomics.
        let overrideInstance: DeclSyntax = """
            /// Replaces a registered type with an instance after construction.
            /// Clears any cached singleton so the next resolve uses the new value.
            public func override<T: Injectable & Sendable>(_ type: T.Type, with instance: T) async {
                await __katanaContainer.override(type, with: instance)
            }
            """

        let overrideFactory: DeclSyntax = """
            /// Replaces a registered type with a factory after construction.
            /// Clears any cached singleton so the next resolve uses the new factory.
            public func override<T: Injectable & Sendable>(
                _ type: T.Type,
                factory: @escaping @Sendable (Container) async -> T
            ) async {
                await __katanaContainer.override(type, factory: factory)
            }
            """

        decls.append(overrideInstance)
        decls.append(overrideFactory)
        return decls
    }

    // MARK: - ExtensionMacro (TestContainerMarker conformance)

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else { return [] }
        let ext = try ExtensionDeclSyntax("extension \(type.trimmed): TestContainerMarker {}")
        return [ext]
    }
}
