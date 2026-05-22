/// Marker protocol applied to every `@Module`-annotated enum.
/// Lets `@Container(modules: [...])` accept a typed list of modules.
public protocol KatanaModule: Sendable {
    static var types: [any (Injectable & Sendable).Type] { get }
}
