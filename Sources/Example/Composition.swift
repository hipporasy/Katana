import Foundation
import Katana

@available(macOS 14, iOS 17, *)
@Container(modules: [
    ServiceModule.self,
    RepositoryModule.self,
    ViewModelModule.self,
])
final class App {}
