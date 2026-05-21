import Foundation
import Katana

// MARK: - Injectable types (the dependency graph)

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

// MARK: - Modules

@Module(Logger.self, AnalyticsClient.self)
enum ServiceModule {}

@Module(TodoRepository.self)
enum RepositoryModule {}
