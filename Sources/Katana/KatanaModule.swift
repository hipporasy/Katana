/// Marker protocol applied automatically to every `@Module`-annotated enum.
///
/// Lets `@KatanaApp(modules: [RepositoryModule.self, ServiceModule.self])`
/// accept any combination of `@Module`-annotated enums as a typed list,
/// instead of `[Any.Type]`.
///
/// The runtime `types` array provided by the macro lets you introspect a
/// module's contents — useful for documentation, tooling, and the
/// `KatanaCodegen` build plugin which reads the list at compile time.
public protocol KatanaModule: Sendable {
    static var types: [any (Injectable & Sendable).Type] { get }
}
