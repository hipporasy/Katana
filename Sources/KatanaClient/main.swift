import Foundation
import Katana

@Injectable
final class Logger: Sendable {
    init() {}
    func log(_ msg: String) { print("[log]", msg) }
}

@Injectable
final class Network: Sendable {
    let logger: Logger
    init(logger: Logger) { self.logger = logger }
    func fetch() { logger.log("fetching…") }
}

@Injectable
final class AuthService: Sendable {
    let network: Network
    let logger: Logger
    init(network: Network, logger: Logger) {
        self.network = network
        self.logger = logger
    }
    func login() {
        logger.log("login starting")
        network.fetch()
    }
}

@Injectable(scope: .transient)
final class RequestContext {
    let id: UUID
    init() { self.id = UUID() }
}

let container = Container()
await container.register(Logger.self)
await container.register(Network.self)
await container.register(AuthService.self)
await container.register(RequestContext.self)

let auth = await container.resolve(AuthService.self)
auth.login()

let authAgain = await container.resolve(AuthService.self)
print("singleton same instance:", auth === authAgain)

let ctx1 = await container.resolve(RequestContext.self)
let ctx2 = await container.resolve(RequestContext.self)
print("transient distinct ids:", ctx1.id != ctx2.id)
