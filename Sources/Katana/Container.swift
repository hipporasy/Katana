public actor Container {
    public init() {}

    private var singletons: [ObjectIdentifier: any Injectable & Sendable] = [:]
    private var sendableFactories: [ObjectIdentifier: SendableEntry] = [:]
    private var transientFactories: [ObjectIdentifier: (Container) async -> any Injectable] = [:]

    private struct SendableEntry {
        let scope: Scope
        let factory: (Container) async -> any Injectable & Sendable
    }

    // MARK: - Register (Sendable types — scope read from T.scope)

    public func register<T: Injectable & Sendable>(_ type: T.Type) {
        sendableFactories[ObjectIdentifier(type)] = SendableEntry(scope: T.scope) { container in
            await T.resolve(from: container)
        }
    }

    public func register<T: Injectable & Sendable>(
        _ type: T.Type,
        factory: @escaping @Sendable (Container) async -> T
    ) {
        sendableFactories[ObjectIdentifier(type)] = SendableEntry(scope: T.scope) { container in
            await factory(container)
        }
    }

    // MARK: - Register (non-Sendable types — implicitly transient)

    public func register<T: Injectable>(_ type: T.Type) {
        transientFactories[ObjectIdentifier(type)] = { container in
            await T.resolve(from: container)
        }
    }

    public func register<T: Injectable>(
        _ type: T.Type,
        factory: @escaping @Sendable (Container) async -> sending T
    ) {
        transientFactories[ObjectIdentifier(type)] = { container in
            await factory(container)
        }
    }

    // MARK: - Override (semantic alias for replacing an earlier registration)

    /// Replaces any prior registration of `type` with a factory that always
    /// returns `instance`. Use this in tests to swap a dependency for a spy,
    /// stub, or pre-built fake.
    ///
    /// Any previously cached singleton for `type` is cleared, so the override
    /// applies even if the type was already resolved.
    public func override<T: Injectable & Sendable>(_ type: T.Type, with instance: T) {
        let key = ObjectIdentifier(type)
        singletons[key] = nil
        sendableFactories[key] = SendableEntry(scope: T.scope) { _ in instance }
    }

    /// Replaces any prior registration of `type` with the given factory. The
    /// cached singleton (if any) is cleared so the next resolve goes through
    /// the new factory.
    public func override<T: Injectable & Sendable>(
        _ type: T.Type,
        factory: @escaping @Sendable (Container) async -> T
    ) {
        let key = ObjectIdentifier(type)
        singletons[key] = nil
        sendableFactories[key] = SendableEntry(scope: T.scope) { container in
            await factory(container)
        }
    }

    /// Replaces any prior registration of a non-`Sendable` transient `type`.
    /// Non-`Sendable` instances cannot be reused across resolves, so the
    /// instance-based `override(_:with:)` does not apply here — use a factory.
    public func override<T: Injectable>(
        _ type: T.Type,
        factory: @escaping @Sendable (Container) async -> sending T
    ) {
        transientFactories[ObjectIdentifier(type)] = { container in
            await factory(container)
        }
    }

    // MARK: - Resolve

    public func resolve<T: Injectable & Sendable>(_ type: T.Type) async -> T {
        let key = ObjectIdentifier(type)
        if let cached = singletons[key] as? T { return cached }

        let value: T
        let scope: Scope
        if let entry = sendableFactories[key] {
            value = await entry.factory(self) as! T
            scope = entry.scope
        } else {
            value = await T.resolve(from: self)
            scope = T.scope
        }
        if scope == .singleton {
            singletons[key] = value
        }
        return value
    }

    public func resolve<T: Injectable>(_ type: T.Type) async -> sending T {
        let key = ObjectIdentifier(type)
        if let factory = transientFactories[key] {
            return await factory(self) as! T
        }
        return await T.resolve(from: self)
    }

    // MARK: - Snapshot

    /// Eagerly resolves every registered singleton and returns a type-erased
    /// `AnyResolver`. Use this at app launch to bridge from the actor's async
    /// API into SwiftUI's sync world (see `@Inject`).
    ///
    /// Transient registrations are intentionally excluded — each transient
    /// resolve must still go through the container so a fresh instance is
    /// produced per call.
    ///
    /// For compile-time-checked typed snapshots, use the `@Container` macro
    /// which generates a nested `Snapshot` type per dependency graph.
    public func snapshot() async -> AnyResolver {
        for (key, entry) in sendableFactories where entry.scope == .singleton {
            if singletons[key] == nil {
                singletons[key] = await entry.factory(self)
            }
        }
        var storage: [ObjectIdentifier: any Sendable] = [:]
        storage.reserveCapacity(singletons.count)
        for (key, value) in singletons {
            storage[key] = value
        }
        return AnyResolver(storage)
    }
}
