import CloudKit
import Foundation

struct BrowserCloudRecordSystemFields: Codable, Equatable, Sendable {
    private(set) var encodedRecordsByName: [String: Data] = [:]

    private var schemaVersionsByName: [String: Int] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case encodedRecordsByName
        case schemaVersionsByName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        encodedRecordsByName = try container.decode([String: Data].self, forKey: .encodedRecordsByName)
        schemaVersionsByName = try container.decodeIfPresent([String: Int].self, forKey: .schemaVersionsByName) ?? [:]
    }

    mutating func update(with record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        encodedRecordsByName[record.recordID.recordName] = archiver.encodedData
        // System-field archives omit custom fields. Retain the schema beside
        // the change tag so a skipped future record cannot become a write base.
        schemaVersionsByName[record.recordID.recordName] = (record["schemaVersion"] as? NSNumber)?.intValue
    }

    mutating func remove(recordName: String) {
        encodedRecordsByName.removeValue(forKey: recordName)
        schemaVersionsByName.removeValue(forKey: recordName)
    }

    func record(for id: CKRecord.ID) -> CKRecord? {
        guard let data = encodedRecordsByName[id.recordName] else { return nil }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            guard let record = CKRecord(coder: unarchiver), record.recordID == id else { return nil }
            if let schema = schemaVersionsByName[id.recordName] {
                record["schemaVersion"] = NSNumber(value: schema)
            }
            return record
        } catch {
            return nil
        }
    }
}
