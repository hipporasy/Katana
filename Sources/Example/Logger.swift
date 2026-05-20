import Foundation
import Katana

/// Tiny logger shared by every layer in the example. Non-`final` so tests can
/// subclass it for spying — see `ExampleTests/SpyLogger`. `Sendable` because
/// the class holds no mutable state; subclasses that add state should adopt
/// `@unchecked Sendable` with appropriate synchronisation.
@Injectable
class Logger: @unchecked Sendable {
    required init() {}
    func log(_ msg: String) { print("[log]", msg) }
}
