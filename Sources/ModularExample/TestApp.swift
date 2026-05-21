import Foundation
import Katana

/// Test peer of `App`. The plugin reads `App`'s module list and generates an
/// extension on `TestApp` with the same typed shape plus post-construction
/// `override(_:with:)` and `TestContainerMarker` conformance.
///
/// Lives in the module so the included `main.swift` can smoke-test the test
/// path; production projects would put `@KatanaTestApp` declarations in their
/// test target.
@KatanaTestApp(of: App.self)
final class TestApp {}
