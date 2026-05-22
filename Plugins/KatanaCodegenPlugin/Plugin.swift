import Foundation
import PackagePlugin

/// SwiftPM build-tool plugin that runs `KatanaCodegen` over the target's Swift
/// sources to generate typed `@Container` / `@TestContainer` extensions, the
/// per-scope `EnvironmentValues` slots, install modifiers, and the bare
/// `@Inject` default-init overload before compilation.
@main
struct KatanaCodegenPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let swiftFiles = sourceTarget.sourceFiles(withSuffix: "swift").map { $0.path }
        guard !swiftFiles.isEmpty else { return [] }

        let outputDir = context.pluginWorkDirectory
        let outputFile = outputDir.appending("KatanaGenerated.swift")
        let codegenTool = try context.tool(named: "KatanaCodegen")

        // Single command per target. Inputs = all .swift sources, output = one
        // generated file. Incremental rebuild kicks in whenever any input
        // file changes.
        let arguments: [String] = ["--output", outputFile.string] + swiftFiles.map { $0.string }

        return [
            .buildCommand(
                displayName: "Katana: generating typed graph for \(target.name)",
                executable: codegenTool.path,
                arguments: arguments,
                inputFiles: swiftFiles,
                outputFiles: [outputFile]
            )
        ]
    }
}
