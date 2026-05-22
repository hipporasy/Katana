import Foundation

/// Validation errors that surface as build failures via stderr in the
/// `KatanaCodegen` executable.
public struct ValidationError: Equatable {
    public let path: String
    public let line: Int
    public let column: Int
    public let message: String

    /// Build-system-friendly format: `path:line:column: error: message`.
    public var formatted: String {
        "\(path):\(line):\(column): error: \(message)"
    }
}

public enum Validator {

    /// Two `@Module`s registering the same type would silently deduplicate at
    /// emission. Surface the conflict explicitly.
    public static func duplicateRegistrations(in modules: [String: ModuleDecl]) -> [ValidationError] {
        var byType: [String: [ModuleDecl]] = [:]
        for module in modules.values {
            for type in module.types {
                byType[type, default: []].append(module)
            }
        }

        var errors: [ValidationError] = []
        for (type, owners) in byType where owners.count > 1 {
            let names = owners.map { $0.name }.sorted().joined(separator: ", ")
            let primary = owners.sorted { $0.name < $1.name }.first!
            errors.append(ValidationError(
                path: primary.path.isEmpty ? "<unknown>" : primary.path,
                line: 1,
                column: 1,
                message: "@Module conflict: \(type) is registered in multiple @Module enums: \(names). Pick one — duplicate registrations silently deduplicate today and may diverge under load."
            ))
        }
        return errors.sorted { $0.message < $1.message }
    }

    public static func unknownModuleReferences(
        containers: [ContainerDecl],
        modules: [String: ModuleDecl]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        for container in containers {
            for ref in container.modules where modules[ref] == nil {
                errors.append(ValidationError(
                    path: container.path.isEmpty ? "<unknown>" : container.path,
                    line: 1,
                    column: 1,
                    message: "@\(container.isTest ? "TestContainer" : "Container")(modules:) on \(container.name) references unknown module `\(ref)`. Add `@Module(...)` to a sibling enum, or fix the reference."
                ))
            }
        }
        return errors
    }

    public static func unknownScopeReferences(
        containers: [ContainerDecl],
        scopes: [ScopeRegistryDecl]
    ) -> [ValidationError] {
        var declared: Set<String> = ["default"]
        for registry in scopes {
            declared.formUnion(registry.cases)
        }
        var errors: [ValidationError] = []
        for container in containers where !declared.contains(container.scope) {
            errors.append(ValidationError(
                path: container.path.isEmpty ? "<unknown>" : container.path,
                line: 1,
                column: 1,
                message: "@\(container.isTest ? "TestContainer" : "Container")(scope: .\(container.scope)) on \(container.name) references an undeclared scope. Add `case \(container.scope)` to a `@Scope` enum."
            ))
        }
        return errors
    }

    /// At most one container per scope per target. Two graphs at the same
    /// scope collide on the `EnvironmentValues.<scope>` accessor and the
    /// `View.katana(_:)` install modifier.
    public static func duplicateScopeBindings(in containers: [ContainerDecl]) -> [ValidationError] {
        var byScope: [String: [ContainerDecl]] = [:]
        for container in containers {
            byScope[container.scope, default: []].append(container)
        }

        var errors: [ValidationError] = []
        for (scope, owners) in byScope where owners.count > 1 {
            let names = owners.map { $0.name }.sorted().joined(separator: ", ")
            let primary = owners.sorted { $0.name < $1.name }.first!
            errors.append(ValidationError(
                path: primary.path.isEmpty ? "<unknown>" : primary.path,
                line: 1,
                column: 1,
                message: "Scope .\(scope) is bound to multiple @Container/@TestContainer declarations: \(names). Each scope may bind to at most one container per target — give the duplicates a custom @Scope case."
            ))
        }
        return errors.sorted { $0.message < $1.message }
    }

    public static func validate(
        containers: [ContainerDecl],
        scopes: [ScopeRegistryDecl],
        modules: [String: ModuleDecl]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        errors.append(contentsOf: duplicateRegistrations(in: modules))
        errors.append(contentsOf: unknownModuleReferences(containers: containers, modules: modules))
        errors.append(contentsOf: unknownScopeReferences(containers: containers, scopes: scopes))
        errors.append(contentsOf: duplicateScopeBindings(in: containers))
        return errors
    }
}
