/// Marker conformance applied to every `@TestContainer`-annotated class.
///
/// Carries no requirements — its sole purpose is to give project-level lint
/// scripts a discoverable hook for enforcing rules like "no `@TestContainer`
/// outside `Tests/`". You should rarely need to reference this directly.
public protocol TestContainerMarker: Sendable {}
