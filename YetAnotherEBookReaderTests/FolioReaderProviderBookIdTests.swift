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
    private var container: AppContainer!
    private var book: CalibreBook!
    private var readerInfo: ReaderInfo!
    private let folioReaderBookId = "Runtime File Name"

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(
            testName: "FolioReaderProviderBookIdTests-\(UUID().uuidString)"
        )

        guard let library = container.libraryManager.calibreLibraries.first?.value else {
            XCTFail("No mock library available")
            return
        }

        book = CalibreBook(id: 901, library: library)
        book.title = "Canonical Test Book"
        readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/\(folioReaderBookId).epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: makePosition(page: 1)
        )

        clearReadingPositions()
        clearBookmarks()
        clearHighlights()
    }

    override func tearDownWithError() throws {
        clearReadingPositions()
        clearBookmarks()
        clearHighlights()
        AppContainer.shared = nil
        container = nil
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
        container.readingPositionRepository.savePosition(savedPosition, for: book)

        let provider = makeReadPositionProvider()
        let restored = provider.folioReaderReadPosition(FolioReader(), bookId: folioReaderBookId)

        XCTAssertEqual(restored?.pageNumber, 14)
        XCTAssertEqual(restored?.pageOffset, CGPoint(x: 22, y: 33))
        XCTAssertEqual(restored?.cfi, "epubcfi(/6/14)")
    }

    func testSavePositionAtomicallyReplacesOlderSameIdentityPosition() throws {
        let oldPosition = makePosition(page: 4, offsetX: 1, offsetY: 2, cfi: "epubcfi(/6/8)", epoch: 1_000)
        let newPosition = makePosition(page: 17, offsetX: 33, offsetY: 44, cfi: "epubcfi(/6/34)", epoch: 2_000)

        container.readingPositionRepository.savePosition(oldPosition, for: book)
        container.readingPositionRepository.savePosition(newPosition, for: book)

        let restored = container.readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container.deviceName))
        XCTAssertEqual(restored?.lastReadPage, 17)
        XCTAssertEqual(restored?.lastPosition, [17, 33, 44])
        XCTAssertEqual(restored?.cfi, "epubcfi(/6/34)")

        let stored = try positionsMatchingIdentity(of: newPosition)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.lastReadPage, 17)
    }

    func testReadPositionProviderReturnsPositionAfterReplacementSave() {
        let oldPosition = makePosition(page: 6, cfi: "epubcfi(/6/12)", epoch: 1_000)
        let newPosition = makePosition(page: 18, offsetX: 9, offsetY: 10, cfi: "epubcfi(/6/36)", epoch: 2_000)
        let provider = makeReadPositionProvider()

        container.readingPositionRepository.savePosition(oldPosition, for: book)
        container.readingPositionRepository.savePosition(newPosition, for: book)

        let restored = provider.folioReaderReadPosition(FolioReader(), bookId: book.bookPrefId)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.pageNumber, 18)
        XCTAssertEqual(restored?.pageOffset, CGPoint(x: 9, y: 10))
        XCTAssertEqual(restored?.cfi, "epubcfi(/6/36)")
    }

    func testConcurrentSaveDoesNotExposeEmptyPositionForSameIdentity() throws {
        let realm = try readingPositionRealm()
        let seedEpoch = Date().timeIntervalSince1970
        try realm.write {
            for index in 0..<1_000 {
                let seededPosition = makePosition(page: 3, cfi: "epubcfi(/6/6)", epoch: seedEpoch - Double(index + 1))
                realm.add(seededPosition.makeRealmObject(bookId: book.bookPrefId))
            }
        }

        let repository = container.readingPositionRepository
        let newPosition = makePosition(page: 19, cfi: "epubcfi(/6/38)", epoch: seedEpoch + 1)
        let writerStarted = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var writerFinished = false
        var sawEmptyPosition = false

        let writerExpectation = expectation(description: "writer finished")
        let readerExpectation = expectation(description: "reader observed non-empty positions")

        DispatchQueue.global(qos: .default).async {
            writerStarted.signal()
            repository.savePosition(newPosition, for: self.book)
            stateLock.lock()
            writerFinished = true
            stateLock.unlock()
            writerExpectation.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            writerStarted.wait()
            while true {
                if repository.getPosition(for: self.book, policy: .latestForDevice(self.container.deviceName)) == nil {
                    stateLock.lock()
                    sawEmptyPosition = true
                    stateLock.unlock()
                    break
                }

                stateLock.lock()
                let done = writerFinished
                stateLock.unlock()
                if done {
                    break
                }
            }
            readerExpectation.fulfill()
        }

        wait(for: [writerExpectation, readerExpectation], timeout: 5.0)
        stateLock.lock()
        let didSeeEmptyPosition = sawEmptyPosition
        stateLock.unlock()
        XCTAssertFalse(didSeeEmptyPosition)
    }

    func testReadPositionProviderRejectsUnrelatedId() {
        let savedPosition = makePosition(page: 8)
        container.readingPositionRepository.savePosition(savedPosition, for: book)

        let provider = makeReadPositionProvider()

        XCTAssertNil(provider.folioReaderReadPosition(FolioReader(), bookId: "unrelated-id"))
        XCTAssertTrue(provider.folioReaderReadPosition(FolioReader(), allByBookId: "unrelated-id").isEmpty)
    }

    func testReadPositionProviderSetCallsCompletionForAcceptedAndRejectedIds() {
        let provider = makeReadPositionProvider()
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

        let stored = container.annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true)
        let runtimeResults = provider.folioReaderBookmark(FolioReader(), allByBookId: folioReaderBookId, andPage: nil)

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.bookId, book.bookPrefId)
        XCTAssertTrue(container.annotationRepository.getBookmarks(forBookId: folioReaderBookId, excludeRemoved: true).isEmpty)
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
        container.readingPositionRepository.savePosition(savedPosition, for: book)

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
        container.annotationRepository.saveHighlight(highlight)

        // 3. Simulate the FolioReaderKit runtime restore path:
        //    the container creates its provider and FolioReaderKit queries by runtime book id
        let container = try makeTestContainer()

        // Position restore
        let positionProvider = makeReadPositionProvider()
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
        let epubContainer = EpubFolioReaderContainer(
            withConfig: config,
            folioReader: folioReader,
            epubPath: "/dev/null/non-existent-\(UUID().uuidString).epub",
            webServer: webServer
        )
        // Ensure the provider factory can build a real FolioReaderDelegateHighlightProvider
        // instead of falling back to FolioReaderDummyHighlightProvider.
        container.sessionManager.readingBook = book
        container.sessionManager.readerInfo = readerInfo
        epubContainer.container = container
        epubContainer.readerEngineDelegate = nil
        // Sanity: the provider must not exist before the fix runs
        epubContainer.folioReaderHighlightProvider = nil
        return epubContainer
    }

    private func makePosition(
        page: Int,
        offsetX: Int = 0,
        offsetY: Int = 0,
        cfi: String = "/",
        epoch: Double = Date().timeIntervalSince1970
    ) -> BookDeviceReadingPosition {
        BookDeviceReadingPosition(
            id: container.deviceName,
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
            epoch: epoch
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
        guard let book,
              let config = container?.serverScopedRealmProvider.configuration(for: book.library.server),
              let realm = try? Realm(configuration: config) else {
            return
        }
        try? realm.write {
            realm.delete(realm.objects(BookDeviceReadingPositionRealm.self))
        }
    }

    private func makeReadPositionProvider() -> FolioReaderYabrReadPositionProvider {
        FolioReaderYabrReadPositionProvider(
            book: book,
            readerInfo: readerInfo,
            readingPositionRepository: container.readingPositionRepository
        )
    }

    private func readingPositionRealm() throws -> Realm {
        let config = container.serverScopedRealmProvider.configuration(for: book.library.server)
        return try Realm(configuration: config)
    }

    private func positionsMatchingIdentity(of position: BookDeviceReadingPosition) throws -> Results<BookDeviceReadingPositionRealm> {
        let realm = try readingPositionRealm()
        return realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(
                format: "bookId == %@ AND deviceId == %@ AND readerName == %@ AND structuralStyle == %@ AND positionTrackingStyle == %@ AND structuralRootPageNumber == %@",
                book.bookPrefId,
                position.id,
                position.readerName,
                NSNumber(value: position.structuralStyle),
                NSNumber(value: position.positionTrackingStyle),
                NSNumber(value: position.structuralRootPageNumber)
            ))
    }

    private func clearBookmarks() {
        guard let realm = container?.databaseService.realm else { return }
        try? realm.write {
            realm.delete(realm.objects(BookBookmarkRealm.self).filter("bookId IN %@", [book?.bookPrefId ?? "", folioReaderBookId]))
        }
    }

    private func clearHighlights() {
        guard let realm = container?.databaseService.realm else { return }
        try? realm.write {
            realm.delete(realm.objects(BookHighlightRealm.self).filter("bookId == %@", book?.bookPrefId ?? ""))
        }
    }

    func testDefaultProfileSeededAndContainsLegacyDefaults() {
        let folioReader = FolioReader()
        let repository = makeProfileRepository(id: "FolioReaderProfileTests")
        let provider = FolioReaderDelegatePreferenceProvider(
            folioReader,
            delegate: nil,
            bookId: book.bookPrefId,
            profileRepository: repository
        )

        // Assert listProfile returns ["Default"]
        let profiles = provider.preference(listProfile: nil)
        XCTAssertTrue(profiles.contains("Default"), "Profiles list should contain 'Default'")

        // Assert loadProfile("Default") populates values
        provider.preference(loadProfile: "Default")

        XCTAssertEqual(provider.preference(intFor: "themeMode", default: -1), FolioReaderThemeMode.serpia.rawValue)
        XCTAssertEqual(provider.preference(boolFor: "nightMode", default: true), false)
        XCTAssertEqual(provider.preference(stringFor: "currentFont", default: ""), "Georgia")
        XCTAssertEqual(provider.preference(stringFor: "currentFontSize", default: ""), FolioReader.DefaultFontSize)
        XCTAssertEqual(provider.preference(stringFor: "currentFontWeight", default: ""), FolioReader.DefaultFontWeight)

        XCTAssertEqual(provider.preference(intFor: "currentMarginTop", default: -1), folioReader.defaultMarginTop)
        XCTAssertEqual(provider.preference(intFor: "currentMarginBottom", default: -1), folioReader.defaultMarginBottom)
        XCTAssertEqual(provider.preference(intFor: "currentMarginLeft", default: -1), folioReader.defaultMarginLeft)
        XCTAssertEqual(provider.preference(intFor: "currentMarginRight", default: -1), folioReader.defaultMarginRight)

        XCTAssertEqual(provider.preference(boolFor: "currentVMarginLinked", default: false), true)
        XCTAssertEqual(provider.preference(boolFor: "currentHMarginLinked", default: false), true)

        XCTAssertEqual(provider.preference(intFor: "currentLetterSpacing", default: -1), FolioReader.DefaultLetterSpacing)
        XCTAssertEqual(provider.preference(intFor: "currentLineHeight", default: -1), FolioReader.DefaultLineHeight)
        XCTAssertEqual(provider.preference(intFor: "currentTextIndent", default: -1), FolioReader.DefaultTextIndent)

        XCTAssertEqual(provider.preference(boolFor: "doWrapPara", default: true), false)
    }

    func testCustomProfileSaveLoadListAndRemove() {
        let folioReader = FolioReader()
        let mockDelegate = MockReaderEngineDelegate()
        let repository = makeProfileRepository(id: "FolioReaderCustomProfileTests")
        let provider = FolioReaderDelegatePreferenceProvider(
            folioReader,
            delegate: mockDelegate,
            bookId: book.bookPrefId,
            profileRepository: repository
        )

        // 1. Initially lists only "Default"
        XCTAssertEqual(provider.preference(listProfile: nil), ["Default"])

        // 2. Change some properties in-memory
        provider.preference(setBool: true, for: "nightMode")
        provider.preference(setInt: 2, for: "themeMode") // Dark theme
        provider.preference(setString: "Avenir", for: "currentFont")

        // 3. Save as custom profile "DarkAvenir"
        provider.preference(saveProfile: "DarkAvenir")

        // 4. Verify listed profiles contains "DarkAvenir"
        let profilesAfterSave = provider.preference(listProfile: nil)
        XCTAssertTrue(profilesAfterSave.contains("DarkAvenir"))
        XCTAssertTrue(profilesAfterSave.contains("Default"))

        // 5. Verify filter works on listProfile
        XCTAssertEqual(provider.preference(listProfile: "Dark"), ["DarkAvenir"])
        XCTAssertEqual(provider.preference(listProfile: "NonExistent"), [])

        // 6. Create a fresh provider instance to test load
        let provider2 = FolioReaderDelegatePreferenceProvider(
            folioReader,
            delegate: mockDelegate,
            bookId: book.bookPrefId,
            profileRepository: repository
        )

        // Before load: has Default profile (e.g. nightMode = false)
        XCTAssertEqual(provider2.preference(boolFor: "nightMode", default: true), false)

        // Load custom profile
        provider2.preference(loadProfile: "DarkAvenir")

        // Verify values are updated
        XCTAssertEqual(provider2.preference(boolFor: "nightMode", default: false), true)
        XCTAssertEqual(provider2.preference(intFor: "themeMode", default: -1), 2)
        XCTAssertEqual(provider2.preference(stringFor: "currentFont", default: ""), "Avenir")

        // Verify delegate was notified on load
        XCTAssertNotNil(mockDelegate.lastUpdatedPreferences)
        XCTAssertEqual(mockDelegate.lastUpdatedPreferences?.themeMode, 2)
        XCTAssertEqual(mockDelegate.lastUpdatedPreferences?.fontFamily, "Avenir")

        // 7. Remove custom profile
        provider2.preference(removeProfile: "DarkAvenir")
        XCTAssertEqual(provider2.preference(listProfile: nil), ["Default"])

        // 8. Remove Default and verify it is recreated on list
        provider2.preference(removeProfile: "Default")
        // listProfile should recreate Default via ensureDefaultProfile()
        XCTAssertEqual(provider2.preference(listProfile: nil), ["Default"])
    }

    func testProviderLoadsDefaultProfileThroughRepositoryOnInit() {
        let folioReader = FolioReader()
        let repository = MockFolioReaderProfileRepository()
        repository.loadProfileReturn = FolioReaderProfileValue(
            nightMode: true,
            themeMode: 2,
            currentFont: "Avenir",
            currentFontSize: "24px",
            currentFontWeight: "700",
            currentScrollDirection: 1,
            currentMarginTop: 9,
            currentMarginBottom: 10,
            currentMarginLeft: 11,
            currentMarginRight: 12,
            currentVMarginLinked: false,
            currentHMarginLinked: false,
            currentLetterSpacing: 3,
            currentLineHeight: 4,
            currentTextIndent: 5,
            doWrapPara: true,
            doClearClass: false
        )

        let provider = FolioReaderDelegatePreferenceProvider(
            folioReader,
            delegate: nil,
            bookId: book.bookPrefId,
            profileRepository: repository
        )

        XCTAssertTrue(repository.ensureDefaultProfileCalled)
        XCTAssertEqual(repository.loadProfileNameParam, "Default")
        XCTAssertEqual(provider.preference(boolFor: "nightMode", default: false), true)
        XCTAssertEqual(provider.preference(stringFor: "currentFont", default: ""), "Avenir")
    }

    func testProviderSaveAndRemoveDelegateToRepository() {
        let folioReader = FolioReader()
        let repository = MockFolioReaderProfileRepository()
        let provider = FolioReaderDelegatePreferenceProvider(
            folioReader,
            delegate: nil,
            bookId: book.bookPrefId,
            profileRepository: repository
        )

        provider.preference(setBool: true, for: "nightMode")
        provider.preference(setString: "Avenir", for: "currentFont")
        provider.preference(saveProfile: "NightAvenir")
        provider.preference(removeProfile: "NightAvenir")

        XCTAssertTrue(repository.saveProfileCalled)
        XCTAssertEqual(repository.saveProfileNameParam, "NightAvenir")
        XCTAssertEqual(repository.saveProfileParam?.nightMode, true)
        XCTAssertEqual(repository.saveProfileParam?.currentFont, "Avenir")
        XCTAssertTrue(repository.removeProfileCalled)
        XCTAssertEqual(repository.removeProfileNameParam, "NightAvenir")
    }

    @MainActor
    func testConcurrentHighlightWriting() throws {
        let repository = container.annotationRepository
        let group = DispatchGroup()
        
        for i in 1...20 {
            group.enter()
            DispatchQueue.global().async {
                let highlight = BookHighlight(
                    id: "highlight-\(i)",
                    bookId: self.book.bookPrefId,
                    readerName: "YabrEPUB",
                    page: 1,
                    startOffset: 0,
                    endOffset: 10,
                    date: Date(),
                    type: 0,
                    note: nil,
                    tocFamilyTitles: [],
                    content: "Text \(i)",
                    contentPost: "",
                    contentPre: "",
                    cfiStart: "epubcfi(/6/4[chap-2]!/4/2/10/1:\(i))",
                    cfiEnd: nil,
                    spineName: nil,
                    ranges: nil,
                    removed: false
                )
                repository.saveHighlight(highlight)
                group.leave()
            }
        }
        
        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success)
        
        container.refreshDatabase()
        
        let retrieved = repository.getHighlights(forBookId: book.bookPrefId, excludeRemoved: false)
        XCTAssertEqual(Set(retrieved.map(\.id)).count, 20)
        XCTAssertEqual(retrieved.filter { $0.id.hasPrefix("highlight-") }.count, 20)
    }

    func testLargeAmountOfBookmarks() throws {
        let provider = FolioReaderYabrBookmarkProvider(book: book, readerInfo: readerInfo)
        
        for i in 1...100 {
            let folioBookmark = makeBookmark(
                bookId: folioReaderBookId,
                page: i,
                pos: "epubcfi(/6/4[chap-2]!/4/2/10/1:\(i))"
            )
            provider.folioReaderBookmark(FolioReader(), added: folioBookmark) { _ in }
        }
        
        let bookmarks = provider.folioReaderBookmark(FolioReader(), allByBookId: folioReaderBookId, andPage: nil)
        XCTAssertEqual(bookmarks.count, 100)
    }

    func testFolioReaderPrecedenceIgnoredInDomain() throws {
        // 1. Domain to Folio conversion must set takePrecedence to false (not propagate to Folio)
        let domainPos = makePosition(page: 12)
        let folioPos = domainPos.toFolioReaderReadPosition()
        XCTAssertFalse(folioPos.takePrecedence)
        
        // 2. Folio to Domain conversion does not hold takePrecedence because domain model has no such field
        let folioPosWithPrecedence = FolioReaderReadPosition(
            deviceId: "test-device",
            structuralStyle: .atom,
            positionTrackingStyle: .linear,
            structuralRootPageNumber: 1,
            pageNumber: 5,
            cfi: "cfi"
        )
        folioPosWithPrecedence.takePrecedence = true
        
        let convertedDomainPos = folioPosWithPrecedence.toBookDeviceReadingPosition()
        XCTAssertEqual(convertedDomainPos.lastReadPage, 5)
        // Check that domain pos converts back to folio without setting takePrecedence to true
        let finalFolioPos = convertedDomainPos.toFolioReaderReadPosition()
        XCTAssertFalse(finalFolioPos.takePrecedence)
    }

    private func makeProfileRepository(id: String) -> FolioReaderProfileRepositoryProtocol {
        let config = Realm.Configuration(
            inMemoryIdentifier: id,
            schemaVersion: AppContainer.RealmSchemaVersion,
            migrationBlock: { _, _ in },
            objectTypes: [FolioReaderPreferenceRealm.self]
        )
        return RealmFolioReaderProfileRepository(realmConfiguration: config)
    }
}

class MockReaderEngineDelegate: ReaderEngineDelegate {
    var lastUpdatedPreferences: ReaderEnginePreferences?

    func readerEngine(_ engine: AnyObject, didUpdatePosition position: ReaderEnginePosition) {}
    func readerEngine(_ engine: AnyObject, didAddHighlight highlight: ReaderEngineHighlight) {}
    func readerEngine(_ engine: AnyObject, didRemoveHighlight highlightId: String) {}
    func readerEngine(_ engine: AnyObject, didUpdatePreferences prefs: ReaderEnginePreferences) {
        lastUpdatedPreferences = prefs
    }
}
