import CloudKit
import Foundation

struct BrowserCloudRecordSystemFields: Codable, Equatable, Sendable {
    private(set) var encodedRecordsByName: [String: Data] = [:]

    mutating func update(with record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        encodedRecordsByName[record.recordID.recordName] = archiver.encodedData
    }

    mutating func remove(recordName: String) {
        encodedRecordsByName.removeValue(forKey: recordName)
    }

    func record(for id: CKRecord.ID) -> CKRecord? {
        guard let data = encodedRecordsByName[id.recordName] else { return nil }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            guard let record = CKRecord(coder: unarchiver), record.recordID == id else { return nil }
            return record
        } catch {
            return nil
        }
    }
}
