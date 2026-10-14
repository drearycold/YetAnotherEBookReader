//
//  CalibreHighlightUUIDTests.swift
//  YetAnotherEBookReaderTests
//
//  Created on 2026/10/14.
//  Calibre keys a highlight by its `uuid`: 16 random bytes in base64url without
//  padding (`short_uuid()` in calibre's viewer). `uuidFolioToCalibre` /
//  `uuidCalibreToFolio` convert between that and the app's UUID strings; their
//  output must not change, or highlights already on calibre stop matching their
//  local copies (calibre merges them by exact `uuid`).
//

import XCTest
@testable import YetAnotherEBookReader

final class CalibreHighlightUUIDTests: XCTestCase {

    /// Computed with the previous implementation (in both -Onone and -O builds), and checked
    /// against Python's `base64.urlsafe_b64encode(uuid.UUID(s).bytes)` and calibre 9.11's own
    /// `urlsafe_b64encode(bytes, "")` from the viewer.
    private let knownVectors: [(folio: String, calibre: String)] = [
        ("00000000-0000-0000-0000-000000000000", "AAAAAAAAAAAAAAAAAAAAAA"),
        ("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", "_____________________w"),
        ("3F2504E0-4F89-11D3-9A0C-0305E82C3301", "PyUE4E-JEdOaDAMF6CwzAQ"),
        ("6BA7B810-9DAD-11D1-80B4-00C04FD430C8", "a6e4EJ2tEdGAtADAT9QwyA"),
        ("FBEFBEFB-FFFF-4F3A-8B2C-9D1E0F7A6B5C", "-----___TzqLLJ0eD3prXA"),
        ("F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6", "-B1Prn3sEdCnZQCgyR5r9g"),
    ]

    func testKnownVectorsConvertToCalibre() {
        for vector in knownVectors {
            XCTAssertEqual(uuidFolioToCalibre(vector.folio), vector.calibre, vector.folio)
        }
    }

    func testKnownVectorsConvertFromCalibre() {
        for vector in knownVectors {
            XCTAssertEqual(uuidCalibreToFolio(vector.calibre), vector.folio, vector.calibre)
        }
    }

    func testLowercaseUUIDGivesSameCalibreId() {
        XCTAssertEqual(uuidFolioToCalibre("f81d4fae-7dec-11d0-a765-00a0c91e6bf6"), "-B1Prn3sEdCnZQCgyR5r9g")
    }

    func testRandomUUIDsRoundTrip() {
        let base64URLCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for _ in 0..<10_000 {
            let uuid = UUID()
            guard let calibreId = uuidFolioToCalibre(uuid.uuidString) else {
                XCTFail("no calibre id for \(uuid)")
                return
            }
            XCTAssertEqual(calibreId.count, 22, uuid.uuidString)
            XCTAssertTrue(calibreId.unicodeScalars.allSatisfy(base64URLCharacters.contains), calibreId)
            XCTAssertEqual(uuidCalibreToFolio(calibreId), uuid.uuidString)
        }
    }

    /// Calibre's ids are random bytes, not version-4 UUIDs, so any 16 bytes must survive.
    func testRandomCalibreIdsRoundTrip() {
        for _ in 0..<10_000 {
            let bytes = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            let calibreId = base64ToBase64URL(base64: bytes.base64EncodedString())
            XCTAssertEqual(uuidCalibreToFolio(calibreId).flatMap(uuidFolioToCalibre), calibreId)
        }
    }

    func testInvalidUUIDStringGivesNil() {
        for identifier in [
            "",
            "not-a-uuid",
            "3F2504E0-4F89-11D3-9A0C-0305E82C330",
            "3F2504E0-4F89-11D3-9A0C-0305E82C33011",
            "3F2504E0-4F89-11D3-9A0C-0305E82C330G",
        ] {
            XCTAssertNil(uuidFolioToCalibre(identifier), identifier)
        }
    }

    func testCalibreIdThatIsNotBase64GivesNil() {
        XCTAssertNil(uuidCalibreToFolio(nil))
        XCTAssertNil(uuidCalibreToFolio("!!!!"))
        XCTAssertNil(uuidCalibreToFolio("AAAAAAAAAAA*AAAAAAAAAA"))
    }

    /// The previous implementation read 16 bytes whatever the decoded length, returning
    /// whatever memory followed a short value.
    func testCalibreIdThatIsNot16BytesGivesNil() {
        for count in [0, 1, 4, 15, 17, 32] {
            let calibreId = base64ToBase64URL(base64: Data(repeating: 0xAB, count: count).base64EncodedString())
            XCTAssertNil(uuidCalibreToFolio(calibreId), "\(count) bytes: \(calibreId)")
        }
        XCTAssertNil(uuidCalibreToFolio("not-a-uuid"), "decodes to 7 bytes")
    }
}
