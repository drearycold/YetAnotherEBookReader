import XCTest
import UIKit
import PDFKit
@testable import YetAnotherEBookReader

/// `yabrPDFOutline(_:for:)` gets the 1-based page number every caller has
/// (`pageRef?.pageNumber`): bookmark titles, bookmark and highlight sections, search results.
@available(iOS 16.0, macCatalyst 16.0, *)
@MainActor
final class YabrEBookReaderPDFMetaSourceTests: XCTestCase {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let pageCount = 7
    /// Each chapter's title and the 1-based page it starts on.
    private static let chapters = [("Chapter 1", 1), ("Chapter 2", 4), ("Chapter 3", 6)]

    func testOutlineOfAChaptersFirstAndLastPage() throws {
        let (metaSource, view) = try makeReader()

        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 1)?.label, "Chapter 1")
        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 3)?.label, "Chapter 1", "a chapter's last page")
        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 4)?.label, "Chapter 2")
        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 5)?.label, "Chapter 2", "a chapter's last page")
        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 6)?.label, "Chapter 3")
        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 7)?.label, "Chapter 3", "the document's last page")
    }

    /// The bookmark and highlight lists key their sections by the chapter's start page.
    func testOutlineOfAChaptersLastPageLeadsToItsStart() throws {
        let (metaSource, view) = try makeReader()

        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 3)?.destination?.page?.pageRef?.pageNumber, 1)
        XCTAssertEqual(metaSource.yabrPDFOutline(view, for: 5)?.destination?.page?.pageRef?.pageNumber, 4)
    }

    func testPagesOutsideTheDocumentHaveNoOutline() throws {
        let (metaSource, view) = try makeReader()

        XCTAssertNil(metaSource.yabrPDFOutline(view, for: 0))
        XCTAssertNil(metaSource.yabrPDFOutline(view, for: -1))
        XCTAssertNil(metaSource.yabrPDFOutline(view, for: Self.pageCount + 1))
    }

    private func makeReader() throws -> (YabrEBookReaderPDFMetaSource, YabrPDFView) {
        let view = YabrPDFView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.document = try makeDocument()
        let metaSource = YabrEBookReaderPDFMetaSource(
            book: TestFixtures.makeBook(),
            readerInfo: ReaderInfo(
                deviceName: "test-device",
                url: URL(fileURLWithPath: "/tmp/test.pdf"),
                missing: false,
                format: .PDF,
                readerType: .YabrPDF,
                position: BookDeviceReadingPosition(readerName: ReaderType.YabrPDF.id)
            ),
            preferenceRepository: StubPDFPreferenceRepository()
        )
        return (metaSource, view)
    }

    /// A line of real text on each page (the lookup selects the page's text), and an outline
    /// starting each chapter at the top of its page.
    private func makeDocument() throws -> PDFDocument {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        let data = renderer.pdfData { context in
            for pageNumber in 1...Self.pageCount {
                context.beginPage()
                "Page \(pageNumber)".draw(at: CGPoint(x: 72, y: 72), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18),
                    .foregroundColor: UIColor.black
                ])
            }
        }
        let document = try XCTUnwrap(PDFDocument(data: data))

        let root = PDFOutline()
        for (index, (title, startPage)) in Self.chapters.enumerated() {
            let item = PDFOutline()
            item.label = title
            // PDF space has its origin bottom-left.
            item.destination = PDFDestination(
                page: try XCTUnwrap(document.page(at: startPage - 1)),
                at: CGPoint(x: 0, y: Self.pageSize.height)
            )
            root.insertChild(item, at: index)
        }
        document.outlineRoot = root

        // Read back from its data, as the reader opens a file.
        let opened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
        XCTAssertEqual(opened.pageCount, Self.pageCount)
        XCTAssertEqual(opened.outlineRoot?.numberOfChildren, Self.chapters.count)
        return opened
    }
}

private final class StubPDFPreferenceRepository: ReaderPreferenceRepositoryProtocol {
    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences? { nil }
    func savePreferences(_ preferences: ReaderEnginePreferences, for book: CalibreBook, readerType: ReaderType) {}
    func loadFolioPreferences(for book: CalibreBook) -> FolioReaderPreferenceValue? { nil }
    func saveFolioPreferences(_ preferences: FolioReaderPreferenceValue, for book: CalibreBook) {}
    func loadReadiumPreferences(for book: CalibreBook) -> ReadiumPreferenceValue? { nil }
    func saveReadiumPreferences(_ preferences: ReadiumPreferenceValue, for book: CalibreBook) {}
    func loadPDFPreferences(for book: CalibreBook) -> PDFPreferenceValue? { nil }
    func savePDFPreferences(_ preferences: PDFPreferenceValue, for book: CalibreBook) {}
}
