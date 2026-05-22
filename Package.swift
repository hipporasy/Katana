// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Katana",
    platforms: [.macOS(.v13), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    // Public products — these are what `swift package` consumers see in the
    // "Add Package Products" dialog. Internal targets (the demo executables,
    // the codegen executable + core, the macro module) stay private to the
    // package so the dependency surface stays small.
    products: [
        .library(name: "Katana", targets: ["Katana"]),
        .plugin(name: "KatanaCodegenPlugin", targets: ["KatanaCodegenPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .macro(
            name: "KatanaMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .target(
            name: "Katana",
            dependencies: ["KatanaMacros"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .executableTarget(
            name: "KatanaClient",
            dependencies: ["Katana"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .executableTarget(
            name: "Example",
            dependencies: ["Katana"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
            plugins: ["KatanaCodegenPlugin"]
        ),
        // MARK: - KatanaCodegen (build plugin's executable + core library)
        .target(
            name: "KatanaCodegenCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .executableTarget(
            name: "KatanaCodegen",
            dependencies: ["KatanaCodegenCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .plugin(
            name: "KatanaCodegenPlugin",
            capability: .buildTool(),
            dependencies: ["KatanaCodegen"]
        ),
        // MARK: - ModularExample (consumer of the plugin)
        .executableTarget(
            name: "ModularExample",
            dependencies: ["Katana"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
            plugins: ["KatanaCodegenPlugin"]
        ),
        .testTarget(
            name: "KatanaTests",
            dependencies: [
                "KatanaMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "ExampleTests",
            dependencies: ["Example", "Katana"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
            plugins: ["KatanaCodegenPlugin"]
        ),
        .testTarget(
            name: "KatanaCodegenTests",
            dependencies: ["KatanaCodegenCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
