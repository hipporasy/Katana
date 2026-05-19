# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift build                                    # Build all targets
swift test                                     # Run all tests
swift test --filter KatanaTests/testMacro      # Run a single test
swift run KatanaClient                         # Run the example client
```

## Design Docs

Before implementing anything, read:
- `Documentation/design.md` — DI architecture, macro contract, scope rules
- `Documentation/swift6.md` — Swift 6 concurrency rules (Container isolation, Sendable requirements, factory closures)

## Architecture

Katana is a Swift 6 macro-based DI framework built with SPM. It uses a three-layer structure required by Swift's macro system:

- **`KatanaMacros`** — Compiler plugin (`.macro` target). Contains the actual macro implementations using `SwiftSyntax`. This target runs at compile time in a separate process.
- **`Katana`** — Public library. Declares macros via `@freestanding`/`@attached` attributes that point to `KatanaMacros` as the implementation. Consumers import this target.
- **`KatanaClient`** — Executable demonstrating macro usage. Imports `Katana`.

Tests live in `KatanaTests` and depend directly on `KatanaMacros` + `SwiftSyntaxMacrosTestSupport`. They use `assertMacroExpansion` to verify the text output of macro expansion — not runtime behavior. New macros need both an entry in `providingMacros` in `KatanaPlugin` and a corresponding `public macro` declaration in `Katana`.
