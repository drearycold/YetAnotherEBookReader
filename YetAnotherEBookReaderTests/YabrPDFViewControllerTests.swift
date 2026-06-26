import XCTest
import UIKit
import PDFKit
@testable import YetAnotherEBookReader

@MainActor
final class YabrPDFViewControllerTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        tempURLs.removeAll()
        PDFPageWithBackground.fillColor = nil
    }

    func testOpenReturnsMinusOneWhenMetaSourceHasNoURL() {
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil)

        XCTAssertEqual(controller.open(), -1)
        XCTAssertNil(controller.pdfView.document)
    }

    func testOpenLoadsPDFAndRestoresInitialPosition() throws {
        let pdfURL = try makePDFURL(name: "open-restores-position", pageCount: 2)
        let options = PDFOptions()
        options.lastScale = 1.75

        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: pdfURL, options: options)
        controller.initialPosition = ReaderEnginePosition(pageNumber: 2, pageOffsetX: 12, pageOffsetY: 34)

        XCTAssertEqual(controller.open(), 0)
        XCTAssertEqual(controller.pdfView.document?.pageCount, 2)
        XCTAssertEqual(controller.pdfView.displayMode, .singlePage)
        XCTAssertEqual(controller.pdfView.displayDirection, .vertical)
        XCTAssertEqual(controller.pageViewPositionHistory[2]?.point, CGPoint(x: 12, y: 34))
        XCTAssertEqual(controller.pageViewPositionHistory[2]?.scaler, CGFloat(options.lastScale))
    }

    func testApplyPreferencesMapsReaderEnginePreferencesToPDFOptions() {
        let controller = SpyYabrPDFViewController()
        let preferences = ReaderEnginePreferences(themeMode: 2, scroll: true, scrollDirection: 1)

        controller.applyPreferences(preferences)

        XCTAssertEqual(controller.pdfOptions.themeMode, .dark)
        XCTAssertEqual(controller.pdfOptions.pageMode, .Scroll)
        XCTAssertEqual(controller.pdfOptions.scrollDirection, .Horizontal)
    }

    func testBuildDefaultMenuItemsWithoutDictViewerReturnsHighlightOnly() {
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil, dictViewer: nil)

        let menuItems = controller.buildDefaultMenuItems()

        XCTAssertEqual(menuItems.count, 1)
        XCTAssertEqual(menuItems.first?.title, "HighlightA")
    }

    func testBuildDefaultMenuItemsWithDictViewerIncludesDictionaryAction() {
        let controller = SpyYabrPDFViewController()
        let dictViewer = UINavigationController(rootViewController: UIViewController())
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil, dictViewer: ("MDict", dictViewer))

        let menuItems = controller.buildDefaultMenuItems()

        XCTAssertEqual(menuItems.count, 2)
        XCTAssertEqual(menuItems[0].title, "HighlightA")
        XCTAssertTrue(menuItems[1].title.contains("MDict"))
    }

    func testHandleScaleChangeUpdatesLastScale() throws {
        let controller = SpyYabrPDFViewController()
        let pdfURL = try makePDFURL(name: "scale-change", pageCount: 1)
        controller.pdfView.document = PDFDocument(url: pdfURL)
        controller.pdfView.minScaleFactor = 1.0
        controller.pdfView.maxScaleFactor = 4.0
        controller.pdfOptions.lastScale = 1.0
        controller.pdfView.scaleFactor = 2.25

        controller.handleScaleChange(nil)

        XCTAssertEqual(controller.pdfOptions.lastScale, 2.25, accuracy: 0.0001)
    }

    func testSharePDFOriginalCreatesTemporaryFileAndPresentsActivityController() throws {
        let pdfURL = try makePDFURL(name: "share-original", pageCount: 1)
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(
            pdfURL: pdfURL,
            title: "Share Book",
            author: "Tester",
            key: "share-original-key"
        )

        controller.sharePDF(annotated: false)

        let tmpFile = expectedSharedPDFURL(bookKey: "share-original-key", title: "Share Book", author: "Tester")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpFile.path))
        XCTAssertTrue(controller.capturedPresentedViewController is UIActivityViewController)
    }

    func testSharePDFAnnotatedWritesPDFAndRestoresFillColor() throws {
        let pdfURL = try makePDFURL(name: "share-annotated", pageCount: 1)
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(
            pdfURL: pdfURL,
            title: "Annotated Book",
            author: "Tester",
            key: "share-annotated-key"
        )
        controller.pdfView.document = PDFDocument(url: pdfURL)

        let originalFillColor = CGColor(gray: 0.3, alpha: 1.0)
        PDFPageWithBackground.fillColor = originalFillColor

        controller.sharePDF(annotated: true)

        let tmpFile = expectedSharedPDFURL(bookKey: "share-annotated-key", title: "Annotated Book", author: "Tester")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpFile.path))
        XCTAssertEqual(PDFPageWithBackground.fillColor, originalFillColor)
        XCTAssertTrue(controller.capturedPresentedViewController is UIActivityViewController)
    }

    private func makePDFURL(name: String, pageCount: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).pdf")

        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
                let text = "Page \(index + 1)"
                text.draw(at: CGPoint(x: 12, y: 12), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18),
                    .foregroundColor: UIColor.black
                ])
            }
            guard let page = PDFPage(image: image) else {
                XCTFail("Unable to create PDF page")
                continue
            }
            document.insert(page, at: index)
        }

        XCTAssertTrue(document.write(to: url))
        tempURLs.append(url)
        return url
    }

    private func expectedSharedPDFURL(bookKey: String, title: String, author: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(bookKey, isDirectory: true)
        tempURLs.append(directory.appendingPathComponent("\(title) - \(author).pdf"))
        return directory.appendingPathComponent("\(title) - \(author).pdf")
    }
}

private final class SpyYabrPDFViewController: YabrPDFViewController {
    private(set) var capturedPresentedViewController: UIViewController?

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        capturedPresentedViewController = viewControllerToPresent
        completion?()
    }
}

private final class MockYabrPDFMetaSource: YabrPDFMetaSource {
    private let pdfURLValue: URL?
    private let title: String
    private let author: String
    private let key: String
    private let dictViewerValue: (String, UINavigationController)?
    private let optionsValue: PDFOptions

    init(
        pdfURL: URL?,
        title: String = "Test Title",
        author: String = "Test Author",
        key: String = "test-key",
        dictViewer: (String, UINavigationController)? = nil,
        options: PDFOptions = PDFOptions()
    ) {
        self.pdfURLValue = pdfURL
        self.title = title
        self.author = author
        self.key = key
        self.dictViewerValue = dictViewer
        self.optionsValue = options
    }

    func yabrPDFBook(_ view: YabrPDFView?, info: String) -> String? {
        switch info {
        case "Title":
            return title
        case "Author":
            return author
        case "Key":
            return key
        default:
            return nil
        }
    }

    func yabrPDFURL(_ view: YabrPDFView?) -> URL? {
        pdfURLValue
    }

    func yabrPDFDocument(_ view: YabrPDFView?) -> PDFDocument? {
        view?.document
    }

    func yabrPDFNavigate(_ view: YabrPDFView?, pageNumber: Int, offset: CGPoint) {
    }

    func yabrPDFNavigate(_ view: YabrPDFView?, destination: PDFDestination) {
    }

    func yabrPDFOutline(_ view: YabrPDFView?, for page: Int) -> PDFOutline? {
        nil
    }

    func yabrPDFOptions(_ view: YabrPDFView?) -> PDFOptions? {
        optionsValue
    }

    func yabrPDFOptions(_ view: YabrPDFView?, update options: PDFOptions) {
        optionsValue.update(other: options)
    }

    func yabrPDFDictViewer(_ view: YabrPDFView?) -> (String, UINavigationController)? {
        dictViewerValue
    }

    func yabrPDFBookmarks(_ view: YabrPDFView?) -> [PDFBookmark] {
        []
    }

    func yabrPDFBookmarks(_ view: YabrPDFView?, update bookmark: PDFBookmark) {
    }

    func yabrPDFBookmarks(_ view: YabrPDFView?, remove bookmark: PDFBookmark) {
    }

    func yabrPDFHighlights(_ view: YabrPDFView?) -> [PDFHighlight] {
        []
    }

    func yabrPDFHighlights(_ view: YabrPDFView?, getById highlightId: UUID) -> PDFHighlight? {
        nil
    }

    func yabrPDFHighlights(_ view: YabrPDFView?, update highlight: PDFHighlight) {
    }

    func yabrPDFHighlights(_ view: YabrPDFView?, remove highlight: PDFHighlight) {
    }

    func yabrPDFReferenceText(_ view: YabrPDFView?) -> String? {
        nil
    }

    func yabrPDFReferenceText(_ view: YabrPDFView?, set refText: String?) {
    }

    func yabrPDFOptionsIsNight<T>(_ view: YabrPDFView?, _ f: T, _ l: T) -> T {
        optionsValue.isDark(f, l)
    }
}
