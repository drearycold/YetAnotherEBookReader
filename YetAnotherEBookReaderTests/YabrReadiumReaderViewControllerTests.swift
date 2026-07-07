import XCTest
import SwiftUI
import UIKit
import ReadiumNavigator
import ReadiumShared
import ReadiumAdapterGCDWebServer
@testable import YetAnotherEBookReader

@MainActor
final class YabrReadiumReaderViewControllerTests: XCTestCase {
    func testInitializerUsesPersistedReadiumPreferencesWhenAvailable() {
        let publication = makePublication()
        let navigator = MockNavigatorViewController(publication: publication)
        let repository = MockReaderPreferenceRepository()
        let book = TestFixtures.makeBook()
        let savedPreferences = ReadiumPreferenceValue(
            id: book.bookPrefId,
            themeMode: 2,
            scroll: false,
            volumeKeyPaging: true,
            verticalMargin: 24
        )
        repository.loadedReadiumPreferences = savedPreferences

        let controller = SpyYabrReadiumReaderViewController(
            navigator: navigator,
            publication: publication,
            initialLocation: nil,
            environment: makeEnvironment(book: book, repository: repository)
        )

        XCTAssertEqual(controller.readiumPreferences, savedPreferences)
        XCTAssertEqual(controller.appliedReadiumPreferences, savedPreferences)
        XCTAssertEqual(navigator.additionalSafeAreaInsets.top, 24)
    }

    func testReaderEngineApplyPreferencesUpdatesLocalReadiumPreferences() {
        let publication = makePublication()
        let navigator = MockNavigatorViewController(publication: publication)
        let controller = SpyYabrReadiumReaderViewController(
            navigator: navigator,
            publication: publication,
            initialLocation: nil,
            environment: makeEnvironment(book: nil, repository: MockReaderPreferenceRepository())
        )
        controller.readiumPreferences = ReadiumPreferenceValue(verticalMargin: 20)

        controller.applyPreferences(ReaderEnginePreferences(
            themeMode: 3,
            fontSizePercentage: 140,
            fontFamily: "Avenir",
            lineHeight: 1.45,
            pageMargins: 1.7,
            scroll: true,
            scrollDirection: 1,
            volumeKeyPaging: true
        ))

        XCTAssertEqual(controller.readiumPreferences?.themeMode, 2)
        XCTAssertEqual(controller.readiumPreferences?.fontSizePercentage, 140)
        XCTAssertEqual(controller.readiumPreferences?.fontFamily, "Avenir")
        XCTAssertEqual(controller.readiumPreferences?.scroll, true)
        XCTAssertEqual(controller.readiumPreferences?.scrollAxis, 1)
        XCTAssertEqual(controller.readiumPreferences?.volumeKeyPaging, true)
        XCTAssertEqual(controller.appliedReadiumPreferences?.themeMode, 2)
        XCTAssertEqual(navigator.additionalSafeAreaInsets, .zero)
    }

    func testPresentSettingsCallbackUpdatesStatePersistsAndNotifiesDelegate() throws {
        let publication = makePublication()
        let navigator = MockNavigatorViewController(publication: publication)
        let repository = MockReaderPreferenceRepository()
        let delegate = MockReadiumReaderEngineDelegate()
        let book = TestFixtures.makeBook()

        let controller = SpyYabrReadiumReaderViewController(
            navigator: navigator,
            publication: publication,
            initialLocation: nil,
            environment: makeEnvironment(book: book, repository: repository)
        )
        controller.readiumPreferences = ReadiumPreferenceValue(id: book.bookPrefId, themeMode: 1, verticalMargin: 10)
        controller.readerEngineDelegate = delegate

        controller.presentSettings()

        let hostingController = try XCTUnwrap(
            controller.capturedPresentedViewController as? UIHostingController<YabrReaderSettingsView>
        )
        hostingController.rootView.model.updateVerticalMargin(30)

        XCTAssertEqual(controller.readiumPreferences?.verticalMargin, 30)
        XCTAssertEqual(controller.appliedReadiumPreferences?.verticalMargin, 30)
        XCTAssertEqual(repository.savedReadiumPreferences?.verticalMargin, 30)
        XCTAssertEqual(repository.savedReadiumBookId, book.id)
        XCTAssertEqual(delegate.lastUpdatedPreferences?.themeMode, 1)
        XCTAssertEqual(delegate.updateCallCount, 1)
    }

    private func makePublication() -> Publication {
        Publication(manifest: Manifest(metadata: Metadata(title: "Readium Test Publication")))
    }

    private func makeEnvironment(book: CalibreBook?, repository: ReaderPreferenceRepositoryProtocol) -> YabrReadiumEnvironment {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
        return YabrReadiumEnvironment(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            httpServer: httpServer,
            book: book,
            readerPreferenceRepository: repository
        )
    }
}

@MainActor
private final class SpyYabrReadiumReaderViewController: YabrReadiumReaderViewController {
    private(set) var appliedReadiumPreferences: ReadiumPreferenceValue?
    private(set) var capturedPresentedViewController: UIViewController?

    override func applyPreferences(_ prefs: ReadiumPreferenceValue) {
        appliedReadiumPreferences = prefs
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        capturedPresentedViewController = viewControllerToPresent
        completion?()
    }
}

@MainActor
private final class MockNavigatorViewController: UIViewController, Navigator {
    let publication: Publication
    var currentLocation: Locator?

    init(publication: Publication) {
        self.publication = publication
        self.currentLocation = nil
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool {
        currentLocation = locator
        return true
    }

    func go(to link: ReadiumShared.Link, options: NavigatorGoOptions) async -> Bool {
        return true
    }

    func goForward(options: NavigatorGoOptions) async -> Bool {
        return true
    }

    func goBackward(options: NavigatorGoOptions) async -> Bool {
        return true
    }
}

private final class MockReaderPreferenceRepository: ReaderPreferenceRepositoryProtocol {
    var loadedInitialPreferences: ReaderEnginePreferences?
    var savedInitialPreferences: ReaderEnginePreferences?
    var loadedReadiumPreferences: ReadiumPreferenceValue?
    var savedReadiumPreferences: ReadiumPreferenceValue?
    var loadedPDFPreferences: PDFPreferenceValue?
    var savedPDFPreferences: PDFPreferenceValue?
    var savedReadiumBookId: Int32?
    var savedPDFBookId: Int32?

    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences? {
        loadedInitialPreferences
    }

    func savePreferences(_ preferences: ReaderEnginePreferences, for book: CalibreBook, readerType: ReaderType) {
        savedInitialPreferences = preferences
    }

    func loadFolioPreferences(for book: CalibreBook) -> FolioReaderPreferenceValue? {
        nil
    }

    func saveFolioPreferences(_ preferences: FolioReaderPreferenceValue, for book: CalibreBook) {
    }

    func loadReadiumPreferences(for book: CalibreBook) -> ReadiumPreferenceValue? {
        loadedReadiumPreferences
    }

    func saveReadiumPreferences(_ preferences: ReadiumPreferenceValue, for book: CalibreBook) {
        savedReadiumPreferences = preferences
        savedReadiumBookId = book.id
    }

    func loadPDFPreferences(for book: CalibreBook) -> PDFPreferenceValue? {
        loadedPDFPreferences
    }

    func savePDFPreferences(_ preferences: PDFPreferenceValue, for book: CalibreBook) {
        savedPDFPreferences = preferences
        savedPDFBookId = book.id
    }
}

private final class MockReadiumReaderEngineDelegate: ReaderEngineDelegate {
    private(set) var lastUpdatedPreferences: ReaderEnginePreferences?
    private(set) var updateCallCount = 0

    func readerEngine(_ engine: AnyObject, didUpdatePosition position: ReaderEnginePosition) {}
    func readerEngine(_ engine: AnyObject, didAddHighlight highlight: ReaderEngineHighlight) {}
    func readerEngine(_ engine: AnyObject, didRemoveHighlight highlightId: String) {}

    func readerEngine(_ engine: AnyObject, didUpdatePreferences prefs: ReaderEnginePreferences) {
        updateCallCount += 1
        lastUpdatedPreferences = prefs
    }
}
