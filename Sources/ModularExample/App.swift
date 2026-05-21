import Foundation
import Katana

/// Composition root assembled from `@Module`s by the `KatanaCodegen` build
/// plugin. The plugin reads the module list, aggregates the types, and emits
/// the typed `init`, `resolve(_:)` overloads, `Snapshot`, and `Inject` in a
/// generated file inside the build directory.
@KatanaApp(modules: [RepositoryModule.self, ServiceModule.self])
final class App {}
