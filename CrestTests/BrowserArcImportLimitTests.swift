import Foundation
import XCTest

@testable import Crest

final class BrowserArcImportLimitTests: XCTestCase {
    func testEmptyRawSpacesDoNotCountTowardTheImportLimit() throws {
        var rawSpaces: [Any] = [
            "imported",
            [
                "id": "imported",
                "title": "Imported",
                "containerIDs": ["root"],
            ],
        ]
        for index in 0...BrowserPortableArchive.maximumSpaceCount {
            rawSpaces.append("empty-\(index)")
            rawSpaces.append([
                "id": "empty-\(index)",
                "title": "Empty \(index)",
                "containerIDs": [],
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "sidebar": [
                "containers": [
                    [
                        "items": [
                            "root",
                            [
                                "id": "root",
                                "childrenIds": ["tab"],
                                "data": ["itemContainer": [:]],
                            ],
                            "tab",
                            [
                                "id": "tab",
                                "data": [
                                    "tab": [
                                        "savedTitle": "Arc",
                                        "savedURL": "https://arc.net/",
                                    ]
                                ],
                            ],
                        ],
                        "spaces": rawSpaces,
                    ]
                ]
            ]
        ])

        let imported = try BrowserTabMigration.decode(
            data,
            source: .arc,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(imported.spaces.map(\.name), ["Imported"])
        XCTAssertEqual(imported.spaces.first?.tabs.map(\.title), ["Arc"])
    }
}
