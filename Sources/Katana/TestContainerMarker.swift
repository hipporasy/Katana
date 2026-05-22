/// Marker conformance applied to every `@TestContainer`-annotated class.
/// No requirements — exists so lint scripts can enforce "no `@TestContainer`
/// outside `Tests/`".
public protocol TestContainerMarker {}
