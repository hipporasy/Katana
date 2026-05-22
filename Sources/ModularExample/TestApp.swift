import Foundation
import Katana

/// Custom scope keeps `TestApp` off `.default`, which `App` already owns in
/// this single-target demo.
@TestContainer(scope: .modularTest, modules: [
    ServiceModule.self,
    RepositoryModule.self,
])
final class TestApp {}
