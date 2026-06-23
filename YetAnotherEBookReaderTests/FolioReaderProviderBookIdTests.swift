//
//  FolioReaderProviderBookIdTests.swift
//  YetAnotherEBookReaderTests
//
//  Verifies that the Yabr FolioReader adapter accepts FolioReaderKit's
//  filename-derived runtime book id while preserving canonical repository ids.
//

import XCTest
import FolioReaderKit
import ReadiumGCDWebServer
import RealmSwift
@testable import YetAnotherEBookReader

final class FolioReaderProviderBookIdTests: XCTestCase {
    private var originalModelDataShared: ModelData?
    private var modelData: ModelData!
    private var book: CalibreBook!
    private var readerInfo: ReaderInfo!
    private let folioReaderBookId = "Runtime File Name"

    override func setUpWithError() throws {
        originalModelDataShared = ModelData.shared
        modelData = ModelData(mock: true)
        ModelData.shared = modelData

        guard let library = modelData.calibreLibraries.first?.value else {
            XCTFail("No mock library available")
            return
        }

        book = CalibreBook(id: 901, library: library)
        book.title = "Canonical Test Book"
        readerInfo = ReaderInfo(
            deviceName: modelData.deviceName,
            url: URL(fileURLWithPath: "/tmp/\(folioReaderBookId).epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: makePosition(page: 1)
        )

        clearReadingPositions()
        clearBookmarks()
    }

    override func tearDownWithError() throws {
        clearReadingPositions()
        clearBookmarks()
        ModelData.shared = originalModelDataShared
        modelData = nil
        book = nil
        readerInfo = nil
    }

    func testBookIdentityAcceptsCanonicalAndFolioReaderRuntimeIds() {
        let identity = FolioReaderBookIdentity(book: book, readerInfo: readerInfo)

        XCTAssertTrue(identity.accepts(book.bookPrefId))
        XCTAssertTrue(identity.accepts(folioReaderBookId))
        XCTAssertEqual(identity.canonicalizing(folioReaderBookId), book.bookPrefId)
        XCTAssertEqual(identity.canonicalizing(book.bookPrefId), book.bookPrefId)
        XCTAssertFalse(identity.accepts("unrelated-id"))
        XCTAssertNil(identity.canonicalizing("unrelated-id"))
    }

    func testReadPositionProviderRestoresCanonicalPositionWithFolioReaderRuntimeId() {
        let savedPosition = makePosition(page: 14, offsetX: 22, offsetY: 33, cfi: "epubcfi(/6/14)")
        modelData.readingPositionRepository.savePosition(savedPosition, forBookId: book.bookPrefId)

        let provider = FolioReaderYabrReadPositionProvider(book: book, readerInfo: readerInfo)
        let restored = provider.folioReaderReadPosition(FolioReader(), bookId: folioReaderBookId)

        XCTAssertEqual(restored?.pageNumber, 14)
        XCTAssertEqual(restored?.pageOffset, CGPoint(x: 22, y: 33))
        XCTAssertEqual(restored?.cfi, "epubcfi(/6/14)")
    }

    func testReadPositionProviderRejectsUnrelatedId() {
        let savedPosition = makePosition(page: 8)
        modelData.readingPositionRepository.savePosition(savedPosition, forBookId: book.bookPrefId)

        let provider = FolioReaderYabrReadPositionProvider(book: book, readerInfo: readerInfo)

        XCTAssertNil(provider.folioReaderReadPosition(FolioReader(), bookId: "unrelated-id"))
        XCTAssertTrue(provider.folioReaderReadPosition(FolioReader(), allByBookId: "unrelated-id").isEmpty)
    }

    func testReadPositionProviderSetCallsCompletionForAcceptedAndRejectedIds() {
        let provider = FolioReaderYabrReadPositionProvider(book: book, readerInfo: readerInfo)
        let position = makePosition(page: 9).toFolioReaderReadPosition()
        var acceptedCompletionCalled = false
        var rejectedCompletionCalled = false

        provider.folioReaderReadPosition(FolioReader(), bookId: folioReaderBookId, set: position) { error in
            XCTAssertNil(error)
            acceptedCompletionCalled = true
        }
        provider.folioReaderReadPosition(FolioReader(), bookId: "unrelated-id", set: position) { error in
            XCTAssertNil(error)
            rejectedCompletionCalled = true
        }

        XCTAssertTrue(acceptedCompletionCalled)
        XCTAssertTrue(rejectedCompletionCalled)
    }

    func testHighlightProviderReturnsCanonicalHighlightsForFolioReaderRuntimeId() {
        let identity = FolioReaderBookIdentity(book: book, readerInfo: readerInfo)
        let provider = FolioReaderDelegateHighlightProvider(delegate: nil, bookIdentity: identity)
        let highlight = makeEngineHighlight(id: "stored-highlight", bookId: book.bookPrefId, page: 3)

        provider.applyHighlights([highlight])
        let results = provider.folioReaderHighlight(FolioReader(), allByBookId: folioReaderBookId, andPage: nil)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bookId, book.bookPrefId)
        XCTAssertEqual(results.first?.highlightId, "stored-highlight")
    }

    func testHighlightProviderCanonicalizesAddedFolioReaderHighlight() {
        let identity = FolioReaderBookIdentity(book: book, readerInfo: readerInfo)
        let provider = FolioReaderDelegateHighlightProvider(delegate: nil, bookIdentity: identity)
        let highlight = makeFolioHighlight(id: "runtime-highlight", bookId: folioReaderBookId, page: 5)
        var completionCalled = false

        provider.folioReaderHighlight(FolioReader(), added: highlight) { error in
            XCTAssertNil(error)
            completionCalled = true
        }
        let results = provider.folioReaderHighlight(FolioReader(), allByBookId: folioReaderBookId, andPage: nil)

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bookId, book.bookPrefId)
        XCTAssertEqual(results.first?.highlightId, "runtime-highlight")
    }

    func testBookmarkProviderCanonicalizesAddedFolioReaderBookmark() {
        let provider = FolioReaderYabrBookmarkProvider(book: book, readerInfo: readerInfo)
        let bookmark = makeBookmark(bookId: folioReaderBookId, page: 6, pos: "epubcfi(/6/6)")
        var completionCalled = false

        provider.folioReaderBookmark(FolioReader(), added: bookmark) { error in
            XCTAssertNil(error)
            completionCalled = true
        }

        let stored = modelData.annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true)
        let runtimeResults = provider.folioReaderBookmark(FolioReader(), allByBookId: folioReaderBookId, andPage: nil)

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.bookId, book.bookPrefId)
        XCTAssertTrue(modelData.annotationRepository.getBookmarks(forBookId: folioReaderBookId, excludeRemoved: true).isEmpty)
        XCTAssertEqual(runtimeResults.first?.bookId, book.bookPrefId)
    }

    // MARK: - Regression tests for FolioReader highlight position restore fix

    func testBookHighlightToFolioReaderHighlightPopulatesEncodedContent() throws {
        let highlight = BookHighlight(
            id: "encoded-1",
            bookId: book.bookPrefId,
            readerName: ReaderType.YabrEPUB.rawValue,
            page: 4,
            startOffset: 10,
            endOffset: 20,
            date: Date(),
            type: BookHighlightStyle.green.rawValue,
            note: nil,
            tocFamilyTitles: ["Chapter 1"],
            content: "hello world",
            contentPost: "after text",
            contentPre: "before text",
            cfiStart: "epubcfi(/6/2[chap01ref])",
            cfiEnd: "epubcfi(/6/4[chap01ref])",
            spineName: "OEBPS/chap01.xhtml",
            ranges: nil,
            removed: false
        )

        let folio = try XCTUnwrap(highlight.toFolioReaderHighlight())

        XCTAssertEqual(folio.contentEncoded, "hello%20world")
        XCTAssertEqual(folio.contentPreEncoded, "before%20text")
        XCTAssertEqual(folio.contentPostEncoded, "after%20text")
    }

    func testHighlightProviderReturnsEncodedHighlightsForFolioReaderRuntimeId() throws {
        let identity = FolioReaderBookIdentity(book: book, readerInfo: readerInfo)
        let provider = FolioReaderDelegateHighlightProvider(delegate: nil, bookIdentity: identity)
        let highlight = makeEngineHighlight(id: "encoded-2", bookId: book.bookPrefId, page: 3)

        provider.applyHighlights([highlight])
        let results = provider.folioReaderHighlight(FolioReader(), allByBookId: folioReaderBookId, andPage: nil)

        XCTAssertEqual(results.count, 1)
        let restored = try XCTUnwrap(results.first)
        XCTAssertEqual(restored.contentEncoded, "highlight")
        XCTAssertNotNil(restored.contentPreEncoded)
        XCTAssertNotNil(restored.contentPostEncoded)
    }

    func testEpubFolioReaderContainerApplyHighlightsCreatesProviderWhenNil() throws {
        let container = try makeTestContainer()
        XCTAssertNil(container.folioReaderHighlightProvider,
                     "Test precondition: provider must be nil before applyHighlights")

        let highlight = makeEngineHighlight(id: "container-1", bookId: book.bookPrefId, page: 2)

        container.applyHighlights([highlight])

        let provider = try XCTUnwrap(
            container.folioReaderHighlightProvider as? FolioReaderDelegateHighlightProvider,
            "applyHighlights should have created and stored a FolioReaderDelegateHighlightProvider"
        )
        let results = provider.folioReaderHighlight(FolioReader(), allByBookId: book.bookPrefId, andPage: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.highlightId, "container-1")
    }

    func testCombinedPositionAndHighlightRestoreViaFolioReaderRuntimeId() throws {
        // 1. Save a canonical reading position
        let savedPosition = makePosition(page: 21, offsetX: 5, offsetY: 7, cfi: "epubcfi(/6/42[chap03ref])")
        modelData.readingPositionRepository.savePosition(savedPosition, forBookId: book.bookPrefId)

        // 2. Save a canonical highlight via the annotation repository
        let highlight = BookHighlight(
            id: "combined-1",
            bookId: book.bookPrefId,
            readerName: ReaderType.YabrEPUB.rawValue,
            page: 21,
            startOffset: 0,
            endOffset: 12,
            date: Date(),
            type: BookHighlightStyle.pink.rawValue,
            note: nil,
            tocFamilyTitles: ["Chapter 3"],
            content: "restore me",
            contentPost: " after",
            contentPre: "before ",
            cfiStart: "epubcfi(/6/42[chap03ref])",
            cfiEnd: "epubcfi(/6/44[chap03ref])",
            spineName: "OEBPS/chap03.xhtml",
            ranges: nil,
            removed: false
        )
        modelData.annotationRepository.saveHighlight(highlight)

        // 3. Simulate the FolioReaderKit runtime restore path:
        //    the container creates its provider and FolioReaderKit queries by runtime book id
        let container = try makeTestContainer()

        // Position restore
        let positionProvider = FolioReaderYabrReadPositionProvider(book: book, readerInfo: readerInfo)
        let restoredPosition = positionProvider.folioReaderReadPosition(
            FolioReader(), bookId: folioReaderBookId
        )
        XCTAssertEqual(restoredPosition?.pageNumber, 21)
        XCTAssertEqual(restoredPosition?.cfi, "epubcfi(/6/42[chap03ref])")

        // Highlight restore through the container (which is what FolioReaderKit calls)
        container.applyHighlights([highlight.toReaderEngineHighlight()])
        let highlightProvider = try XCTUnwrap(
            container.folioReaderHighlightProvider as? FolioReaderDelegateHighlightProvider
        )
        let runtimeHighlights = highlightProvider.folioReaderHighlight(
            FolioReader(), allByBookId: folioReaderBookId, andPage: nil
        )

        XCTAssertEqual(runtimeHighlights.count, 1)
        let restoredHighlight = try XCTUnwrap(runtimeHighlights.first)
        XCTAssertEqual(restoredHighlight.bookId, book.bookPrefId,
                       "Runtime query must resolve to canonical book id")
        XCTAssertEqual(restoredHighlight.contentEncoded, "restore%20me",
                       "Encoded content must be populated so Bridge.js decodeURIComponent does not throw")
    }

    // MARK: - Helpers

    private func makeTestContainer() throws -> EpubFolioReaderContainer {
        let config = FolioReaderConfig(withIdentifier: "TEST-\(UUID().uuidString)")
        let folioReader = FolioReader()
        let webServer = ReadiumGCDWebServer()
        let container = EpubFolioReaderContainer(
            withConfig: config,
            folioReader: folioReader,
            epubPath: "/dev/null/non-existent-\(UUID().uuidString).epub",
            webServer: webServer
        )
        // Ensure the provider factory can build a real FolioReaderDelegateHighlightProvider
        // instead of falling back to FolioReaderDummyHighlightProvider.
        modelData.sessionManager.readingBook = book
        modelData.sessionManager.readerInfo = readerInfo
        container.modelData = modelData
        container.readerEngineDelegate = nil
        // Sanity: the provider must not exist before the fix runs
        container.folioReaderHighlightProvider = nil
        return container
    }

    private func makePosition(page: Int, offsetX: Int = 0, offsetY: Int = 0, cfi: String = "/") -> BookDeviceReadingPosition {
        BookDeviceReadingPosition(
            id: modelData.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue,
            maxPage: 120,
            lastReadPage: page,
            lastReadChapter: "Chapter \(page)",
            lastChapterProgress: 40,
            lastProgress: 50,
            furthestReadPage: page,
            furthestReadChapter: "Chapter \(page)",
            lastPosition: [page, offsetX, offsetY],
            cfi: cfi,
            epoch: Date().timeIntervalSince1970
        )
    }

    private func makeEngineHighlight(id: String, bookId: String, page: Int) -> ReaderEngineHighlight {
        ReaderEngineHighlight(
            id: id,
            bookId: bookId,
            readerName: ReaderType.YabrEPUB.rawValue,
            page: page,
            startOffset: 1,
            endOffset: 4,
            date: Date(),
            type: BookHighlightStyle.yellow.rawValue,
            content: "highlight"
        )
    }

    private func makeFolioHighlight(id: String, bookId: String, page: Int) -> FolioReaderHighlight {
        let highlight = FolioReaderHighlight()
        highlight.highlightId = id
        highlight.bookId = bookId
        highlight.page = page
        highlight.startOffset = 1
        highlight.endOffset = 4
        highlight.date = Date()
        highlight.type = BookHighlightStyle.yellow.rawValue
        highlight.content = "highlight"
        highlight.contentPre = "before"
        highlight.contentPost = "after"
        highlight.cfiStart = "epubcfi(/6/2)"
        highlight.cfiEnd = "epubcfi(/6/4)"
        highlight.style = FolioReaderHighlightStyle.classForStyle(BookHighlightStyle.yellow.rawValue)
        return highlight
    }

    private func makeBookmark(bookId: String, page: Int, pos: String) -> FolioReaderBookmark {
        let bookmark = FolioReaderBookmark()
        bookmark.bookId = bookId
        bookmark.page = page
        bookmark.pos_type = "epubcfi"
        bookmark.pos = pos
        bookmark.title = "Bookmark \(page)"
        bookmark.date = Date()
        return bookmark
    }

    private func clearReadingPositions() {
        guard let book = book else { return }
        let components = book.bookPrefId.components(separatedBy: " - ")
        guard components.count > 1,
              let library = modelData?.calibreLibraries.values.first(where: { $0.key == components[0] }),
              let realm = try? Realm(configuration: BookAnnotation.getBookPreferenceServerConfig(library.server)) else {
            return
        }
        try? realm.write {
            realm.delete(realm.objects(BookDeviceReadingPositionRealm.self))
        }
    }

    private func clearBookmarks() {
        guard let realm = modelData?.realm else { return }
        try? realm.write {
            realm.delete(realm.objects(BookBookmarkRealm.self).filter("bookId IN %@", [book?.bookPrefId ?? "", folioReaderBookId]))
        }
    }
}
