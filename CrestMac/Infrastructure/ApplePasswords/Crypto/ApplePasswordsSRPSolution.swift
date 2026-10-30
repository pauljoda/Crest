import Foundation

/// Everything one run of the SRP exchange derives from the helper's challenge
/// and the typed code. The intermediate values are kept so tests can check each
/// step against known vectors; all of it is secret and lives in memory only.
struct ApplePasswordsSRPSolution {
    /// `u`, the scrambling parameter, as minimal big-endian bytes.
    let scrambler: Data
    /// `k`, the multiplier.
    let multiplier: Data
    /// `x`, the private exponent from the salt and the code.
    let privateExponent: Data
    /// `S`, the shared secret, as minimal big-endian bytes.
    let sharedSecret: Data
    /// `K`, SHA-256 of the minimal bytes of `S`: 32 bytes.
    let sessionKey: Data
    /// `M`, the proof Crest sends.
    let clientProof: Data
    /// `HAMK`, the proof Crest expects back.
    let expectedServerProof: Data

    /// Whether the helper's proof matches, compared in constant time.
    func verifies(serverProof: Data) -> Bool {
        guard serverProof.count == expectedServerProof.count else { return false }
        var difference: UInt8 = 0
        for (expected, received) in zip(expectedServerProof, serverProof) {
            difference |= expected ^ received
        }
        return difference == 0
    }
}
