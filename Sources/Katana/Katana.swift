/// Marks a type as resolvable by the `Container`. The macro inspects the type's
/// primary initializer and synthesizes an `Injectable` conformance whose
/// `resolve(from:)` method asks the container for each dependency in order.
///
/// ```swift
/// @Injectable
/// final class AuthService: Sendable {
///     init(network: NetworkService, logger: LoggerService) { ... }
/// }
/// ```
///
/// Pass `scope: .transient` to opt out of singleton caching. Singleton-scoped
/// types must be `Sendable`; transient types may be non-`Sendable`.
@attached(extension, conformances: Injectable, names: named(resolve), named(scope))
public macro Injectable(scope: Scope = .singleton) =
    #externalMacro(module: "KatanaMacros", type: "InjectableMacro")
