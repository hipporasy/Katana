import Foundation
import Katana

@Injectable
class Logger: @unchecked Sendable {
    required init() {}
    func log(_ msg: String) { print("[modular-log]", msg) }
}

@Injectable
actor TodoRepository {
    private var storage: [String] = []
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func add(_ title: String) {
        storage.append(title)
        logger.log("added \(title)")
    }

    func all() -> [String] { storage }
}

@Injectable
final class AnalyticsClient: Sendable {
    let logger: Logger
    init(logger: Logger) { self.logger = logger }
    func track(_ event: String) { logger.log("analytics: \(event)") }
}

@Module(Logger.self, AnalyticsClient.self)
enum ServiceModule {}

@Module(TodoRepository.self)
enum RepositoryModule {}

/// `App` binds to `.default`. `TestApp` uses `.modularTest` because both live
/// in the same target — production code would normally split them across
/// targets and both could use `.default`.
@Scope
enum ModularExampleScope {
    case modularTest
}
