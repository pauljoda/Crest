import Foundation

/// The versioned descriptor shared by native page ports and message adapters.
/// A declaration describes this adapter's integration, not every feature of its engine.
struct BrowserAdapterRegistration: Encodable, Sendable {

    // MARK: - Types

    /// The adapter slot the descriptor fills in the core's session contract.
    enum Adapter: String, Encodable, Sendable {
        case engine
    }

    /// Matches `CrestCore.Contracts.Protocol.CapabilityStatuses`.
    enum Status: String, Encodable, Sendable {
        case supported
        case unverified
        case unavailable
    }

    struct Capability: Encodable, Sendable {
        let status: Status
        let contractVersion = 1
        let scope: String
        let limitations: [String]
        let evidence: String
    }

    private enum CodingKeys: String, CodingKey {
        case adapterId, role, implementationId, implementationVersion
        case protocolVersion, capabilities
    }

    // MARK: - Variables

    let capabilities: [BrowserEngineCapability: Capability]
    let adapterId: Adapter
    let role: Adapter
    let implementationId: BrowserEngineImplementation
    let implementationVersion = "1"
    let protocolVersion = 1
    /// The page archive this engine writes and reads. It follows the engine, not
    /// the platform, so callers that have no page yet can still name the format
    /// without asking a compile-time condition. Not part of the encoded
    /// descriptor: the core session contract is the capability map.
    let archiveFormat: BrowserPageArchiveFormat

    // MARK: - Initializers

    init(
        adapter: Adapter = .engine, implementation: BrowserEngineImplementation, scope: String,
        supported: [BrowserEngineCapability], unverified: [BrowserEngineCapability] = [],
        unavailable: [BrowserEngineCapability] = [], limitations: [String] = [],
        archiveFormat: BrowserPageArchiveFormat, evidence: String
    ) {
        adapterId = adapter
        role = adapter
        implementationId = implementation
        self.archiveFormat = archiveFormat
        var values: [BrowserEngineCapability: Capability] = [:]
        for (status, declared) in [
            (Status.supported, supported), (.unverified, unverified), (.unavailable, unavailable),
        ] {
            for capability in declared {
                precondition(values[capability] == nil, "Duplicate adapter capability: \(capability.rawValue)")
                values[capability] = Capability(
                    status: status, scope: scope, limitations: limitations,
                    evidence: evidence)
            }
        }
        capabilities = values
    }

    // MARK: - Actions - Capabilities

    func supports(_ capability: BrowserEngineCapability) -> Bool {
        guard let declared = capabilities[capability] else { return false }
        return declared.status == .supported && declared.contractVersion == 1
    }

    // MARK: - Actions - Encoding

    func encoded() throws -> Data { try JSONEncoder().encode(self) }
}
