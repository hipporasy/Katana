import XCTest
@testable import KatanaCodegenCore

final class ValidatorTests: XCTestCase {

    func testNoErrorsForCleanGraph() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger", "Network"], path: "Service.swift"),
            "Repo": ModuleDecl(name: "Repo", types: ["TodoRepository"], path: "Repo.swift"),
        ]
        let containers = [ContainerDecl(name: "App", modules: ["Service", "Repo"])]
        let errors = Validator.validate(containers: containers, scopes: [], modules: modules)
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Module-level

    func testFlagsDuplicateRegistration() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger"], path: "Service.swift"),
            "Other": ModuleDecl(name: "Other", types: ["Logger"], path: "Other.swift"),
        ]
        let errors = Validator.duplicateRegistrations(in: modules)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("Logger"))
        XCTAssertTrue(errors[0].message.contains("Other"))
        XCTAssertTrue(errors[0].message.contains("Service"))
    }

    // MARK: - Container-level

    func testFlagsUnknownModuleReference() {
        let modules: [String: ModuleDecl] = [:]
        let containers = [ContainerDecl(name: "App", modules: ["MissingModule"])]
        let errors = Validator.unknownModuleReferences(containers: containers, modules: modules)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("MissingModule"))
        XCTAssertTrue(errors[0].message.contains("App"))
    }

    func testFlagsUnknownScopeReference() {
        let containers = [
            ContainerDecl(name: "Checkout", scope: "checkout", modules: []),
        ]
        // No @Scope declares `.checkout` anywhere.
        let errors = Validator.unknownScopeReferences(containers: containers, scopes: [])
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains(".checkout"))
        XCTAssertTrue(errors[0].message.contains("@Scope"))
    }

    func testKnownScopesPass() {
        let containers = [
            ContainerDecl(name: "Checkout", scope: "checkout", modules: []),
        ]
        let scopes = [ScopeRegistryDecl(name: "AppScope", cases: ["checkout"])]
        let errors = Validator.unknownScopeReferences(containers: containers, scopes: scopes)
        XCTAssertTrue(errors.isEmpty)
    }

    func testDefaultScopeIsAlwaysKnown() {
        let containers = [
            ContainerDecl(name: "App", scope: "default", modules: []),
        ]
        let errors = Validator.unknownScopeReferences(containers: containers, scopes: [])
        XCTAssertTrue(errors.isEmpty)
    }

    func testFlagsDuplicateScopeBindings() {
        let containers = [
            ContainerDecl(name: "App", scope: "default", modules: []),
            ContainerDecl(name: "Other", scope: "default", modules: []),
        ]
        let errors = Validator.duplicateScopeBindings(in: containers)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains(".default"))
        XCTAssertTrue(errors[0].message.contains("App"))
        XCTAssertTrue(errors[0].message.contains("Other"))
    }

    func testDistinctScopesDoNotConflict() {
        let containers = [
            ContainerDecl(name: "App", scope: "default", modules: []),
            ContainerDecl(name: "Checkout", scope: "checkout", modules: []),
        ]
        let errors = Validator.duplicateScopeBindings(in: containers)
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Format

    func testFormattedErrorMatchesBuildSystemConvention() {
        let err = ValidationError(path: "foo.swift", line: 3, column: 12, message: "boom")
        XCTAssertEqual(err.formatted, "foo.swift:3:12: error: boom")
    }
}
