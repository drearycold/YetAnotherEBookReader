import XCTest
@testable import YetAnotherEBookReader

/// YabrPDF needs iOS 16 / Mac Catalyst 16; older systems read PDFs in Readium PDF.
final class ReaderTypeAvailabilityTests: XCTestCase {
    func testYabrPDFFallsBackToReadiumWhenUnavailable() {
        XCTAssertEqual(ReaderType.YabrPDF.resolved(yabrPDFAvailable: false), .ReadiumPDF)
        XCTAssertEqual(ReaderType.YabrPDF.resolved(yabrPDFAvailable: true), .YabrPDF)
    }

    func testOtherReadersAreNeverRemapped() {
        for reader in ReaderType.allCases where reader != .YabrPDF {
            XCTAssertEqual(reader.resolved(yabrPDFAvailable: false), reader, "\(reader)")
            XCTAssertEqual(reader.resolved(yabrPDFAvailable: true), reader, "\(reader)")
        }
    }

    func testPDFReadersOfferedPerAvailability() {
        XCTAssertEqual(ReaderType.readers(for: .PDF, yabrPDFAvailable: true), [.YabrPDF, .ReadiumPDF])
        XCTAssertEqual(ReaderType.readers(for: .PDF, yabrPDFAvailable: false), [.ReadiumPDF])
        XCTAssertEqual(ReaderType.readers(for: .EPUB, yabrPDFAvailable: false), [.YabrEPUB, .ReadiumEPUB])
        XCTAssertEqual(ReaderType.readers(for: .CBZ, yabrPDFAvailable: false), [.ReadiumCBZ])
        XCTAssertEqual(ReaderType.readers(for: .UNKNOWN), [])
    }

    func testReaderInfoResolvesOnThisSystem() {
        let info = ReaderInfo(
            deviceName: "device",
            url: URL(fileURLWithPath: "/tmp/book.pdf"),
            missing: false,
            format: .PDF,
            readerType: .YabrPDF,
            position: BookDeviceReadingPosition(readerName: ReaderType.YabrPDF.id)
        )

        XCTAssertEqual(info.readerType, ReaderType.YabrPDF.resolved())
    }

    func testPDFReaderChoicesRespectTheRunningSystem() {
        if #available(iOS 16.0, macCatalyst 16.0, *) {
            XCTAssertEqual(ReaderType.readers(for: .PDF), [.YabrPDF, .ReadiumPDF])
        } else {
            XCTAssertEqual(ReaderType.readers(for: .PDF), [.ReadiumPDF])
        }
    }
}
