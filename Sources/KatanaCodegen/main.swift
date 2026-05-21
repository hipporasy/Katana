import Foundation
import KatanaCodegenCore

// MARK: - Argument parsing

let allArgs = Array(CommandLine.arguments.dropFirst())
guard let outputIdx = allArgs.firstIndex(of: "--output"),
      outputIdx + 1 < allArgs.count
else {
    FileHandle.standardError.write(Data("error: KatanaCodegen requires --output <path>\n".utf8))
    exit(1)
}

let outputPath = allArgs[outputIdx + 1]
var inputPaths: [String] = []
var i = 0
while i < allArgs.count {
    if allArgs[i] == "--output" {
        i += 2          // skip flag + value
        continue
    }
    inputPaths.append(allArgs[i])
    i += 1
}

// MARK: - Scan

let scanner = Scanner()
for path in inputPaths {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
    scanner.scan(source: source, path: path)
}

// MARK: - Validate

let errors = Validator.validate(
    apps: scanner.apps,
    testApps: scanner.testApps,
    modules: scanner.modules
)

if !errors.isEmpty {
    for error in errors {
        FileHandle.standardError.write(Data((error.formatted + "\n").utf8))
    }
    exit(1)
}

// MARK: - Emit

let generated = Emitter.emit(
    apps: scanner.apps,
    testApps: scanner.testApps,
    modules: scanner.modules
)

try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
