import CloudKit
import Foundation

struct BrowserCloudSyncState: Codable, Sendable {
    var engineStateSerialization: CKSyncEngine.State.Serialization?
    var systemFields: BrowserCloudRecordSystemFields
    var reconciliationReason: BrowserCloudReconciliationReason?
    var conflictResolution: BrowserCloudConflictResolution?

    var requiresAccountConfirmation: Bool {
        reconciliationReason == .accountChange
    }

    init(
        engineStateSerialization: CKSyncEngine.State.Serialization? = nil,
        systemFields: BrowserCloudRecordSystemFields = BrowserCloudRecordSystemFields(),
        reconciliationReason: BrowserCloudReconciliationReason? = nil,
        conflictResolution: BrowserCloudConflictResolution? = nil
    ) {
        self.engineStateSerialization = engineStateSerialization
        self.systemFields = systemFields
        self.reconciliationReason = reconciliationReason
        self.conflictResolution = conflictResolution
    }

    private enum CodingKeys: String, CodingKey {
        case engineStateSerialization
        case systemFields
        case reconciliationReason
        case requiresAccountConfirmation
        case conflictResolution
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engineStateSerialization = try container.decodeIfPresent(
            CKSyncEngine.State.Serialization.self,
            forKey: .engineStateSerialization
        )
        systemFields =
            try container.decodeIfPresent(
                BrowserCloudRecordSystemFields.self,
                forKey: .systemFields
            ) ?? BrowserCloudRecordSystemFields()
        conflictResolution = try container.decodeIfPresent(
            BrowserCloudConflictResolution.self,
            forKey: .conflictResolution
        )
        if let reason = try container.decodeIfPresent(
            BrowserCloudReconciliationReason.self,
            forKey: .reconciliationReason
        ) {
            reconciliationReason = reason
        } else if try container.decodeIfPresent(
            Bool.self,
            forKey: .requiresAccountConfirmation
        ) == true {
            // Older builds paused the entire dataset for an ordinary record
            // race. Preserve the migration signal without continuing the pause.
            reconciliationReason = .legacyRecordConflict
        } else {
            reconciliationReason = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(
            engineStateSerialization,
            forKey: .engineStateSerialization
        )
        try container.encode(systemFields, forKey: .systemFields)
        try container.encodeIfPresent(
            reconciliationReason,
            forKey: .reconciliationReason
        )
        try container.encodeIfPresent(
            conflictResolution,
            forKey: .conflictResolution
        )
    }
}
