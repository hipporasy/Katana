import Foundation
import Katana

@Container(modules: [
    ServiceModule.self,
    RepositoryModule.self,
])
final class App {}
