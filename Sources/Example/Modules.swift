import Foundation
import Katana

@Module(Logger.self)
enum ServiceModule {}

@Module(TodoRepository.self)
enum RepositoryModule {}

@available(macOS 14, iOS 17, *)
@Module(TodoListViewModel.self)
enum ViewModelModule {}
