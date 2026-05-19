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
}
