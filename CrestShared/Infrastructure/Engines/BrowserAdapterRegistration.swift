import Foundation

/// What one engine's integration offers: the engine it is, the capabilities it
/// supports, and the page archive it writes. The core hears those
/// capabilities when the engine's binding registers.
struct BrowserAdapterRegistration: Sendable {

    // MARK: - Variables

    let kind: EngineKind
    let capabilities: Set<EngineCapability>
    let implementationId: BrowserEngineImplementation
    /// The page archive this engine writes and reads. It follows the engine, not
    /// the platform, so callers that have no page yet can still name the format
    /// without asking a compile-time condition.
    let archiveFormat: BrowserPageArchiveFormat

    // MARK: - Initializers

    init(
        kind: EngineKind, implementation: BrowserEngineImplementation, supported: [EngineCapability],
        archiveFormat: BrowserPageArchiveFormat
    ) {
        precondition(Set(supported).count == supported.count, "Duplicate engine capability")
        self.kind = kind
        implementationId = implementation
        self.archiveFormat = archiveFormat
        capabilities = Set(supported)
    }

    // MARK: - Actions - Capabilities

    func supports(_ capability: EngineCapability) -> Bool {
        capabilities.contains(capability)
    }

    /// What the engine's binding registers with the core: the capabilities it
    /// supports, in the core's order.
    func registration(isDefault: Bool) -> EngineRegistration {
        EngineRegistration(kind: kind, capabilities: EngineCapability.all.filter(supports), isDefault: isDefault)
    }
}
