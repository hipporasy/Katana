public protocol Injectable {
    static var scope: Scope { get }
    static func resolve(from container: Container) async -> sending Self
}

extension Injectable {
    public static var scope: Scope { .singleton }
}
