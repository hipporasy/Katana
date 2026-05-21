public actor Container {
    public init() {}

    /// Composite key used internally to identify registrations. Unnamed
    /// registrations have `name == nil`; named bindings supply a stable
    /// string identifier that lets multiple instances of the same `Type`
    /// coexist in the container.
    private struct Key: Hashable, Sendable {
        let type: ObjectIdentifier
        let name: String?
    }

    private var singletons: [Key: any Injectable & Sendable] = [:]
    private var sendableFactories: [Key: SendableEntry] = [:]
    private var transientFactories: [Key: (Container) async -> any Injectable] = [:]

    private struct SendableEntry {
        let scope: Scope
        let factory: (Container) async -> any Injectable & Sendable
    }

    // MARK: - Cycle detection

    /// Chain of types currently being resolved on this task. Used by the
    /// `resolve` overloads to detect cyclic dependencies and trap with a
    /// readable description.
    ///
    /// Stored as a task-local so it propagates through nested `resolve` calls
    /// — including those inside macro-generated `T.resolve(from:)` and inside
    /// factory closures — without threading state through every signature.
    ///
    /// Exposed publicly mostly for diagnostics and tests; do not mutate
    /// directly (use `$resolutionChain.withValue` if you need to override).
    @TaskLocal public static var resolutionChain: [String] = []

    private static func cycleTrap(adding label: String) -> Never {
        let chain = (Container.resolutionChain + [label]).joined(separator: " → ")
        preconditionFailure("""
            Cyclic dependency detected during resolve: \(chain)

            This usually means a type depends transitively on itself. Break the cycle by:
              - introducing a protocol abstraction between the involved types, or
              - making one side a transient lazy lookup instead of a constructor parameter, or
              - rethinking the ownership so one type holds the other rather than vice versa.
            """)
    }

    private static func chainLabel<T>(_ type: T.Type, name: String?) -> String {
        let base = String(reflecting: type)
        if let name { return "\(base)[\(name)]" }
        return base
    }

    // MARK: - Register (Sendable types — scope read from T.scope)

    public func register<T: Injectable & Sendable>(
        _ type: T.Type,
        name: String? = nil
    ) {
        sendableFactories[Key(type: ObjectIdentifier(type), name: name)] = SendableEntry(scope: T.scope) { container in
            await T.resolve(from: container)
        }
    }

    public func register<T: Injectable & Sendable>(
        _ type: T.Type,
        name: String? = nil,
        factory: @escaping @Sendable (Container) async -> T
    ) {
        sendableFactories[Key(type: ObjectIdentifier(type), name: name)] = SendableEntry(scope: T.scope) { container in
            await factory(container)
        }
    }

    // MARK: - Register (non-Sendable types — implicitly transient)

    public func register<T: Injectable>(
        _ type: T.Type,
        name: String? = nil
    ) {
        transientFactories[Key(type: ObjectIdentifier(type), name: name)] = { container in
            await T.resolve(from: container)
        }
    }

    public func register<T: Injectable>(
        _ type: T.Type,
        name: String? = nil,
        factory: @escaping @Sendable (Container) async -> sending T
    ) {
        transientFactories[Key(type: ObjectIdentifier(type), name: name)] = { container in
            await factory(container)
        }
    }

    // MARK: - Override (semantic alias for replacing an earlier registration)

    public func override<T: Injectable & Sendable>(
        _ type: T.Type,
        name: String? = nil,
        with instance: T
    ) {
        let key = Key(type: ObjectIdentifier(type), name: name)
        singletons[key] = nil
        sendableFactories[key] = SendableEntry(scope: T.scope) { _ in instance }
    }

    public func override<T: Injectable & Sendable>(
        _ type: T.Type,
        name: String? = nil,
        factory: @escaping @Sendable (Container) async -> T
    ) {
        let key = Key(type: ObjectIdentifier(type), name: name)
        singletons[key] = nil
        sendableFactories[key] = SendableEntry(scope: T.scope) { container in
            await factory(container)
        }
    }

    public func override<T: Injectable>(
        _ type: T.Type,
        name: String? = nil,
        factory: @escaping @Sendable (Container) async -> sending T
    ) {
        transientFactories[Key(type: ObjectIdentifier(type), name: name)] = { container in
            await factory(container)
        }
    }

    // MARK: - Resolve

    public func resolve<T: Injectable & Sendable>(
        _ type: T.Type,
        name: String? = nil
    ) async -> T {
        let key = Key(type: ObjectIdentifier(type), name: name)
        if let cached = singletons[key] as? T { return cached }

        let label = Container.chainLabel(type, name: name)
        if Container.resolutionChain.contains(label) {
            Container.cycleTrap(adding: label)
        }

        return await Container.$resolutionChain.withValue(Container.resolutionChain + [label]) {
            await self.resolveUncachedSendable(type, key: key, name: name)
        }
    }

    private func resolveUncachedSendable<T: Injectable & Sendable>(
        _ type: T.Type,
        key: Key,
        name: String?
    ) async -> T {
        let value: T
        let scope: Scope
        if let entry = sendableFactories[key] {
            value = await entry.factory(self) as! T
            scope = entry.scope
        } else if name == nil {
            // Auto-resolve only kicks in for the default (unnamed) binding.
            value = await T.resolve(from: self)
            scope = T.scope
        } else {
            preconditionFailure("No factory registered for \(type) with name \"\(name!)\". Call container.register(_:name:factory:) before resolving named bindings.")
        }
        if scope == .singleton {
            singletons[key] = value
        }
        return value
    }

    public func resolve<T: Injectable>(
        _ type: T.Type,
        name: String? = nil
    ) async -> sending T {
        // Cycle detection: shallow check only on the non-Sendable path. The
        // `sending T` return type cannot pass through a `withValue` closure
        // without confusing Swift 6's sending-isolation analysis, so we
        // detect cycles into a non-Sendable transient but don't extend the
        // chain across it. In practice cycles are rare here — transient
        // types are typically lightweight per-request values.
        let label = Container.chainLabel(type, name: name)
        if Container.resolutionChain.contains(label) {
            Container.cycleTrap(adding: label)
        }

        let key = Key(type: ObjectIdentifier(type), name: name)
        if let factory = transientFactories[key] {
            return await factory(self) as! T
        }
        if name != nil {
            preconditionFailure("No factory registered for transient \(type) with name \"\(name!)\". Call container.register(_:name:factory:) before resolving.")
        }
        return await T.resolve(from: self)
    }

    // MARK: - Snapshot

    /// Eagerly resolves every registered **unnamed** singleton and returns a
    /// type-erased `AnyResolver`. Named bindings are container-level only and
    /// do not participate in the synchronous snapshot — they remain accessible
    /// via `await container.resolve(_:name:)`.
    ///
    /// For compile-time-checked typed snapshots, use the `@Container` macro
    /// which generates a nested `Snapshot` type per dependency graph.
    public func snapshot() async -> AnyResolver {
        for (key, entry) in sendableFactories where entry.scope == .singleton && key.name == nil {
            if singletons[key] == nil {
                singletons[key] = await entry.factory(self)
            }
        }
        var storage: [ObjectIdentifier: any Sendable] = [:]
        storage.reserveCapacity(singletons.count)
        for (key, value) in singletons where key.name == nil {
            storage[key.type] = value
        }
        return AnyResolver(storage)
    }
}
