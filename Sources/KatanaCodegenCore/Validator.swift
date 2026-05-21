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

    /// Scans for cross-module duplicate registrations. Two `@Module`s
    /// registering the same type would silently deduplicate at emission, so
    /// flag it explicitly — the user almost certainly meant for the type to
    /// live in exactly one module.
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

    /// Verifies every `@KatanaApp(modules: [...])` reference resolves to a
    /// discovered `@Module` enum in the same target.
    public static func unknownModuleReferences(
        apps: [AppDecl],
        modules: [String: ModuleDecl]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        for app in apps {
            for ref in app.modules where modules[ref] == nil {
                errors.append(ValidationError(
                    path: "<unknown>",
                    line: 1,
                    column: 1,
                    message: "@KatanaApp(modules:) on \(app.name) references unknown module `\(ref)`. Add `@Module(...)` to a sibling enum, or fix the reference."
                ))
            }
        }
        return errors
    }

    /// Verifies every `@KatanaTestApp(of: X.self)` resolves to a discovered
    /// `@KatanaApp` declaration.
    public static func unknownTestAppReferences(
        testApps: [TestAppDecl],
        apps: [AppDecl]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        let appNames = Set(apps.map { $0.name })
        for testApp in testApps where !appNames.contains(testApp.productionApp) {
            errors.append(ValidationError(
                path: "<unknown>",
                line: 1,
                column: 1,
                message: "@KatanaTestApp(of: \(testApp.productionApp).self) on \(testApp.name) references unknown @KatanaApp. Ensure the production graph is declared in the same target."
            ))
        }
        return errors
    }

    /// Runs every validator and returns the union of errors.
    public static func validate(
        apps: [AppDecl],
        testApps: [TestAppDecl],
        modules: [String: ModuleDecl]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        errors.append(contentsOf: duplicateRegistrations(in: modules))
        errors.append(contentsOf: unknownModuleReferences(apps: apps, modules: modules))
        errors.append(contentsOf: unknownTestAppReferences(testApps: testApps, apps: apps))
        return errors
    }
}
