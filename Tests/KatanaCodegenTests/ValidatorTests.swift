import XCTest
@testable import KatanaCodegenCore

final class ValidatorTests: XCTestCase {

    func testNoErrorsForCleanGraph() {
        let modules = [
            "Service": ModuleDecl(name: "Service", types: ["Logger", "Network"], path: "Service.swift"),
            "Repo": ModuleDecl(name: "Repo", types: ["TodoRepository"], path: "Repo.swift"),
        ]
        let apps = [AppDecl(name: "App", modules: ["Service", "Repo"])]
        let errors = Validator.validate(apps: apps, testApps: [], modules: modules)
        XCTAssertTrue(errors.isEmpty)
    }

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

    func testFlagsUnknownModuleReference() {
        let modules: [String: ModuleDecl] = [:]
        let apps = [AppDecl(name: "App", modules: ["MissingModule"])]
        let errors = Validator.unknownModuleReferences(apps: apps, modules: modules)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("MissingModule"))
        XCTAssertTrue(errors[0].message.contains("App"))
    }

    func testFlagsUnknownTestAppReference() {
        let apps = [AppDecl(name: "App", modules: [])]
        let testApps = [TestAppDecl(name: "TestX", productionApp: "MissingApp")]
        let errors = Validator.unknownTestAppReferences(testApps: testApps, apps: apps)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("MissingApp"))
    }

    func testFormattedErrorMatchesBuildSystemConvention() {
        let err = ValidationError(path: "foo.swift", line: 3, column: 12, message: "boom")
        XCTAssertEqual(err.formatted, "foo.swift:3:12: error: boom")
    }
}
