import XCTest
import SwiftUI
import Combine
import UIKit
import WebKit
import PDFKit
import Zip
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
class BookDetailViewModelTests: XCTestCase {
    
    var viewModel: BookDetailViewModel!
    var mockAppContainer: AppContainer!
    var mockBookRealm: CalibreBookRealm!
    var mockCalibreBook: CalibreBook!

    var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "BookDetailViewModelTests")
        // AppContainer.shared is set by MockAppContainerFactory.makeContainer
        viewModel = BookDetailViewModel(container: mockAppContainer)

        let server = CalibreServer(
            uuid: UUID(),
            name: "Book Detail Test Server",
            baseUrl: "http://localhost",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        let library = CalibreLibrary(server: server, key: "lib1", name: "Library 1")
        try mockAppContainer.serverRepository.saveServer(server)
        mockAppContainer.calibreServers[server.id] = server
        try mockAppContainer.libraryRepository.saveLibrary(library)
        mockAppContainer.calibreLibraries[library.id] = library

        let probeRequest = CalibreProbeServerRequest(
            server: server,
            isPublic: false,
            updateLibrary: false,
            autoUpdateOnly: false
        )
        let serverInfo = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: "http://localhost")!,
            reachable: true,
            probing: false,
            errorMsg: "Success",
            defaultLibrary: library.id,
            libraryMap: [library.id: library.name],
            request: probeRequest
        )
        mockAppContainer.calibreServerInfoStaging = [server.uuid.uuidString: serverInfo]
        
        mockBookRealm = CalibreBookRealm()
        mockBookRealm.serverUUID = library.server.uuid.uuidString
        mockBookRealm.libraryName = library.name
        mockBookRealm.idInLib = 123
        mockBookRealm.title = "Test Book"
        mockBookRealm.updatePrimaryKey()
        
        mockCalibreBook = CalibreBook(id: 123, library: library)
        mockCalibreBook.title = "Test Book"
        
        try! mockAppContainer.databaseService.realm!.write {
            mockAppContainer.databaseService.realm!.add(mockBookRealm, update: .modified)
        }
        
        viewModel.setup(bookId: mockBookRealm.primaryKey!)
        clearReadingPositions()
    }

    override func tearDownWithError() throws {
        if let library = mockAppContainer?.calibreLibraries.first?.value {
            try? mockAppContainer?.databaseService.realm!.write {
                if let serverRealm = mockAppContainer?.databaseService.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                    serverRealm.dsreaderHelper = nil
                }
            }
        }
        clearReadingPositions()
        
        AppContainer.shared = nil
        viewModel = nil
        mockAppContainer = nil
        mockBookRealm = nil
        mockCalibreBook = nil
        cancellables.removeAll()
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        pollNanoseconds: UInt64 = 100_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().timeIntervalSince1970 + (Double(timeoutNanoseconds) / 1_000_000_000)
        while Date().timeIntervalSince1970 < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }
    
    private func clearReadingPositions() {
        guard let calibreBook = mockCalibreBook,
              let config = mockAppContainer?.serverScopedRealmProvider.configuration(for: calibreBook.library.server),
              let realm = try? Realm(configuration: config) else {
            return
        }
        try? realm.write {
            realm.delete(realm.objects(BookDeviceReadingPositionRealm.self))
        }
    }

    func testMissingBookClearsPreviousDetail() throws {
        XCTAssertFalse(viewModel.setup(bookId: "missing-book"))
        XCTAssertNil(viewModel.calibreBook)
    }

    func testDeletedBookClearsObservedDetail() async throws {
        mockAppContainer.bookRepository.deleteBook(id: mockCalibreBook.inShelfId)
        await waitUntil { self.viewModel.calibreBook == nil }
        XCTAssertNil(viewModel.calibreBook)
    }

    func testConcurrentRefreshesUseEachBooksOwnResult() async throws {
        let controller = DetailRefreshController()
        let firstBook = try XCTUnwrap(mockCalibreBook)
        let secondBook = CalibreBook(id: firstBook.id,
            library: CalibreLibrary(server: firstBook.library.server, key: "other", name: "Other"))
        let firstRepo = MockBookRepository()
        firstRepo.getBookReturn = firstBook
        let secondRepo = MockBookRepository()
        secondRepo.getBookReturn = secondBook
        let first = BookDetailViewModel(container: mockAppContainer, bookRepository: firstRepo,
            refreshMetadata: controller.refresh)
        let second = BookDetailViewModel(container: mockAppContainer, bookRepository: secondRepo,
            refreshMetadata: controller.refresh)
        first.onAppear(bookId: firstBook.inShelfId, targetWorkspaceID: nil)
        second.onAppear(bookId: secondBook.inShelfId, targetWorkspaceID: nil)
        await waitUntil { controller.requests.count == 2 }
        XCTAssertEqual(controller.requests.map { $0.library.id }, [firstBook.library.id, secondBook.library.id])
        controller.complete(1, with: .updated)
        await waitUntil { second.refreshState == .synced }
        XCTAssertEqual(first.refreshState, .refreshing)
        mockAppContainer.updatingMetadataStatus = "Deleted"
        controller.complete(0, with: .failed("First server failed"))
        await waitUntil { first.refreshState == .failed("First server failed") }
        XCTAssertEqual(second.refreshState, .synced)
        XCTAssertEqual(first.calibreBook?.inShelfId, firstBook.inShelfId)
        XCTAssertEqual(second.calibreBook?.inShelfId, secondBook.inShelfId)
        first.onDisappear()
        second.onDisappear()
    }

    func testRetryIgnoresLateFailureAndKeepsReadableCacheWhenRemoteUnavailable() async throws {
        var book = try makeDownloadReadBook()
        book.formats["EPUB"]?.cached = true
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try Data("EPUB".utf8).write(to: url)
        mockAppContainer.bookRepository.saveBook(book)
        let controller = DetailRefreshController()
        let model = BookDetailViewModel(container: mockAppContainer, refreshMetadata: controller.refresh)
        model.onAppear(bookId: book.inShelfId, targetWorkspaceID: nil)
        await waitUntil { controller.requests.count == 1 }
        model.refresh(book: book)
        await waitUntil { controller.requests.count == 2 }
        controller.complete(1, with: .unavailable)
        await waitUntil { model.refreshState == .unavailable }
        controller.complete(0, with: .failed("Late failure"))
        await Task.yield()
        XCTAssertEqual(model.refreshState, .unavailable)
        XCTAssertEqual(model.formatStates.first?.statusText, "Downloaded")
        XCTAssertEqual(model.formatStates.first?.statusIcon, "checkmark.circle")
        XCTAssertEqual(model.pageState, .content)
        XCTAssertEqual(model.readActionTitle(for: book), "Read")
        model.readBook(book: book)
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.book.inShelfId, book.inShelfId)
        model.onDisappear()
    }

    func testSwitchingLibrariesIgnoresOldRequestAndBookObservation() async throws {
        let book = try XCTUnwrap(mockCalibreBook)
        var other = CalibreBook(id: book.id,
            library: CalibreLibrary(server: book.library.server, key: "second", name: "Second"))
        other.title = "Second Book"
        let repository = MockBookRepository()
        repository.getBookReturn = book
        let controller = DetailRefreshController()
        let model = BookDetailViewModel(container: mockAppContainer, bookRepository: repository,
            refreshMetadata: controller.refresh)
        model.onAppear(bookId: book.inShelfId, targetWorkspaceID: nil)
        await waitUntil { controller.requests.count == 1 }
        repository.getBookReturn = other
        model.onAppear(bookId: other.inShelfId, targetWorkspaceID: nil)
        await waitUntil { controller.requests.count == 2 }
        controller.complete(0, with: .unavailable)
        repository.sendObservedBook(book)
        await Task.yield()
        XCTAssertEqual(model.calibreBook?.inShelfId, other.inShelfId)
        XCTAssertEqual(model.refreshState, .refreshing)
        controller.complete(1, with: .updated)
        await waitUntil { model.refreshState == .synced }
        XCTAssertEqual(model.calibreBook?.title, "Second Book")
        model.onDisappear()
    }

    func testCancelledRefreshAndDetachedObservationsCannotChangeDetail() async throws {
        let book = try XCTUnwrap(mockCalibreBook)
        let repository = MockBookRepository()
        repository.getBookReturn = book
        let controller = DetailRefreshController()
        let model = BookDetailViewModel(container: mockAppContainer, bookRepository: repository,
            refreshMetadata: controller.refresh)
        model.onAppear(bookId: book.inShelfId, targetWorkspaceID: nil)
        await waitUntil { controller.requests.count == 1 }
        model.cancelRefresh()
        controller.complete(0, with: .unavailable)
        await Task.yield()
        XCTAssertEqual(model.refreshState, .idle)
        model.refresh(book: book)
        await waitUntil { controller.requests.count == 2 }
        model.onDisappear()
        repository.sendObservedBook(nil)
        controller.complete(1, with: .failed("Late result after leaving"))
        await Task.yield()
        XCTAssertEqual(model.pageState, .content)
        XCTAssertEqual(model.refreshState, .idle)
        XCTAssertEqual(model.calibreBook?.inShelfId, book.inShelfId)
    }

    func testMissingObservedBookCanReappearWithoutStaleHistory() async throws {
        let repository = MockBookRepository()
        let book = try XCTUnwrap(mockCalibreBook)
        let model = BookDetailViewModel(container: mockAppContainer, bookRepository: repository)
        XCTAssertFalse(model.setup(bookId: book.inShelfId))
        XCTAssertEqual(model.pageState, .unavailable)
        repository.sendObservedBook(book)
        await waitUntil { model.pageState == .content }
        XCTAssertEqual(model.calibreBook?.inShelfId, book.inShelfId)
        repository.sendObservedBook(nil)
        await waitUntil { model.pageState == .unavailable }
        XCTAssertNil(model.calibreBook)
        XCTAssertFalse(model.hasHistory)
        model.onDisappear()
    }

    func testPositionEventsUpdateProgressWithoutBookMetadataChanges() async throws {
        let positions = MockReadingPositionRepository()
        let book = try XCTUnwrap(mockCalibreBook)
        let model = BookDetailViewModel(container: mockAppContainer, readingPositionRepository: positions)
        model.setup(bookId: book.inShelfId)
        let savedPosition = BookDeviceReadingPosition(id: mockAppContainer.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue, lastReadPage: 9, lastProgress: 45, epoch: 123)
        positions.getPositionsReturn = [savedPosition]
        positions.positionsBroadcaster.send([savedPosition])
        await waitUntil { model.hasHistory }
        XCTAssertEqual(model.readingProgressSummary, .localProgress(percent: 45, device: mockAppContainer.deviceName))
        positions.getPositionsReturn = []
        positions.positionsBroadcaster.send([])
        await waitUntil { !model.hasHistory }
        XCTAssertNil(model.readingProgressSummary)
        model.onDisappear()
    }

    func testPersistedPositionChangesUpdateDetailWithoutMetadataChanges() async throws {
        let position = BookDeviceReadingPosition(id: mockAppContainer.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue, lastReadPage: 17, lastProgress: 68, epoch: Date().timeIntervalSince1970)
        mockAppContainer.readingPositionRepository.savePosition(position, for: mockCalibreBook)
        await waitUntil { self.viewModel.hasHistory }
        XCTAssertEqual(viewModel.readingProgressSummary, .localProgress(percent: 68, device: mockAppContainer.deviceName))
        mockAppContainer.readingPositionRepository.removePosition(deviceName: position.id, for: mockCalibreBook)
        await waitUntil { !self.viewModel.hasHistory }
        XCTAssertFalse(viewModel.hasHistory)
        XCTAssertNil(viewModel.readingProgressSummary)
    }

    func testRenderingAndPresentationGettersDoNotQueryRepositoriesFilesOrPrepareReader() async throws {
        var book = try XCTUnwrap(mockCalibreBook)
        book.formats["EPUB"] = FormatInfo(selected: true, filename: "render.epub", serverSize: 10,
            serverMTime: Date(), cached: true, cacheSize: 10, cacheMTime: Date(), manifest: nil)
        let repository = MockBookRepository()
        repository.getBookReturn = book
        let positions = MockReadingPositionRepository()
        var fileQueries = 0
        let model = BookDetailViewModel(container: mockAppContainer, bookRepository: repository,
            readingPositionRepository: positions, fileExists: { _ in fileQueries += 1; return true })
        model.setup(bookId: book.inShelfId)
        // Drain initial stream snapshots before measuring rendering itself.
        await Task.yield()
        await Task.yield()
        repository.getBookCalled = false
        positions.getPositionsCalled = false
        positions.createInitialCalled = false
        let queriesBefore = fileQueries
        let host = UIHostingController(rootView: NavigationView {
            BookDetailContentView(book: book,
                overview: BookOverviewView(book: book, availableWidth: 358, canRead: model.canRead(book),
                    waitingToRead: model.isWaitingToRead(book), hasActiveDownload: model.hasActiveDownload(book),
                    readActionTitle: model.readActionTitle(for: book), read: {}, downloadOnly: {}, cancelDownload: {}),
                progress: BookProgressSection(summary: model.getReadingProgressSummary(for: book),
                    hasHistory: model.hasReadingHistory(for: book), showHistory: {}),
                formats: BookFormatList(rows: []),
                metadata: BookMetadataSection(book: book, goodreadsRating: model.ratingGRDescription(for: book),
                    goodreadsShelves: model.goodreadsShelves(for: book)),
                connectivity: BookConnectivitySection(book: book, refreshState: model.refreshState,
                    showFailure: { _ in }, retry: {}, showActivity: {}), countPages: nil)
                .toolbar { BookDetailToolbar(viewModel: model) }
        })
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.layoutIfNeeded()
        for _ in 0..<50 {
            XCTAssertEqual(model.readActionTitle(for: book), "Read")
            XCTAssertTrue(model.canRead(book))
            _ = model.hasReadingHistory(for: book)
            _ = model.getReadingProgressSummary(for: book)
            _ = model.getActiveDownload(book: book, format: .EPUB)
            _ = model.countPagesConfiguration(for: book.library)
        }
        XCTAssertFalse(repository.getBookCalled)
        XCTAssertFalse(positions.getPositionsCalled)
        XCTAssertFalse(positions.createInitialCalled)
        XCTAssertEqual(fileQueries, queriesBefore)
        model.onDisappear()
    }

    func testRefreshDoesNotKeepViewModelAlive() async throws {
        let controller = DetailRefreshController()
        var model: BookDetailViewModel? = BookDetailViewModel(container: mockAppContainer,
            refreshMetadata: controller.refresh)
        model?.onAppear(bookId: mockCalibreBook.inShelfId, targetWorkspaceID: nil)
        await waitUntil { controller.requests.count == 1 }
        let weakModel = { [weak model] in model }
        model = nil
        XCTAssertNil(weakModel())
        controller.complete(0, with: .updated)
        await Task.yield()
    }

    func testPreviewDiscardsPendingRead() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        _ = viewModel.previewAction(book: book, format: .EPUB, formatInfo: try XCTUnwrap(book.formats["EPUB"]))
        XCTAssertFalse(viewModel.isWaitingToRead(book))
        try await completeReadDownload(download)
        await Task.yield()
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testCachedReadRechecksFileAtClickTime() throws {
        var book = try makeDownloadReadBook()
        book.formats["EPUB"]?.cached = true
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try Data("EPUB".utf8).write(to: url)
        mockAppContainer.bookRepository.saveBook(book)
        viewModel.setup(bookId: book.inShelfId)
        XCTAssertTrue(viewModel.canRead(book))
        try FileManager.default.removeItem(at: url)
        viewModel.readBook(book: book)
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        XCTAssertTrue(viewModel.isWaitingToRead(book))
        viewModel.cancelReadDownload(book: book)
    }

    func testSwitchingBooksRevokesTheOldDownloadReadIntent() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        var other = CalibreBook(id: book.id,
            library: CalibreLibrary(server: book.library.server, key: "other", name: "Other"))
        other.title = "Other Book"
        try mockAppContainer.libraryRepository.saveLibrary(other.library)
        mockAppContainer.calibreLibraries[other.library.id] = other.library
        mockAppContainer.bookRepository.saveBook(other)
        XCTAssertTrue(viewModel.setup(bookId: other.inShelfId))
        XCTAssertFalse(viewModel.isWaitingToRead(book))
        try await completeReadDownload(download)
        await Task.yield()
        XCTAssertEqual(viewModel.calibreBook?.inShelfId, other.inShelfId)
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testCancellationWhileMetadataWriteIsPendingKeepsCommittedStateConsistent() async throws {
        try await assertCancelledMetadataWriteConsistency(blockAfterCommit: false)
    }

    func testCancellationAfterMetadataCommitKeepsCommittedStateConsistent() async throws {
        try await assertCancelledMetadataWriteConsistency(blockAfterCommit: true)
    }

    private func assertCancelledMetadataWriteConsistency(blockAfterCommit: Bool) async throws {
        var book = try makeDownloadReadBook()
        book.inShelf = true
        book.formats["EPUB"]?.cached = true
        mockAppContainer.bookRepository.saveBook(book)
        var entry = CalibreBookEntry()
        entry.title = "Committed New Title"
        entry.formats = ["epub"]
        entry.format_metadata = ["epub": .init(size: 1024, mtime: "2026-11-06T00:00:00Z")]
        let payload = try JSONEncoder().encode([String(book.id): entry])
        configureMetadataResponse(body: try XCTUnwrap(String(data: payload, encoding: .utf8)))

        let reachedBoundary = expectation(description: "metadata persistence boundary reached")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let repository = PausingMetadataBookRepository(databaseService: mockAppContainer.databaseService,
            libraryResolver: mockAppContainer)
        repository.blockAfterCommit = blockAfterCommit
        repository.atBoundary = {
            reachedBoundary.fulfill()
            _ = release.wait(timeout: .now() + 10)
        }
        let manager = CalibreBookManager(container: mockAppContainer,
            databaseService: mockAppContainer.databaseService, bookRepository: repository)
        manager.booksInShelf[book.inShelfId] = book
        var status = CalibreSyncStatus(library: book.library)
        status.del = [book.id]
        mockAppContainer.librarySyncStatus[book.library.id] = status
        let notified = expectation(description: "committed book update published")
        let updates = mockAppContainer.calibreUpdates()
        let observer = Task { @MainActor in
            for await signal in updates {
                if case .book(let updated) = signal,
                   updated.inShelfId == book.inShelfId, updated.title == entry.title {
                    notified.fulfill()
                    return
                }
            }
        }
        defer { observer.cancel() }
        let refresh = Task { await manager.getBooksMetadata(
            request: .init(library: book.library, books: [book.id], getAnnotations: false)) }
        await fulfillment(of: [reachedBoundary], timeout: 5)
        refresh.cancel()
        release.signal()
        let result = await refresh.value
        mockAppContainer.refreshDatabase()
        XCTAssertEqual(result[book.id], .cancelled)
        XCTAssertEqual(repository.getBook(id: book.inShelfId)?.title, entry.title)
        XCTAssertEqual(manager.booksInShelf[book.inShelfId]?.title, entry.title)
        XCTAssertFalse(mockAppContainer.librarySyncStatus[book.library.id]?.del.contains(book.id) ?? true)
        await fulfillment(of: [notified], timeout: 2)
        await manager.clearCache(inShelfId: book.inShelfId)
        XCTAssertEqual(repository.getBook(id: book.inShelfId)?.title, entry.title,
                       "Clearing cache must not overwrite committed metadata with the old shelf snapshot")
    }

    private func configureMetadataResponse(status: Int = 200, body: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        for timeout in [10.0, 600.0] {
            let key = CalibreServerURLSessionKey(server: mockCalibreBook.library.server, timeout: timeout, qos: .default)
            mockAppContainer.calibreServerService.metadataSessions[key] = session
        }
        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url),
                statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return (response, Data(body.utf8))
        }
    }

    func testManagerReturnsUnavailableWithoutDeletingLocalBook() async throws {
        configureMetadataResponse(body: "{\"123\":null}")
        let result = await mockAppContainer.bookManager.getBooksMetadata(
            request: .init(library: mockCalibreBook.library, books: [123], getAnnotations: false))
        XCTAssertEqual(result[123], .unavailable)
        XCTAssertNotNil(mockAppContainer.bookRepository.getBook(id: mockCalibreBook.inShelfId))
    }

    func testManagerReturnsRefreshFailure() async throws {
        configureMetadataResponse(status: 503, body: "<html>" + String(repeating: "Proxy failed ", count: 10_000) + "</html>")
        let result = await mockAppContainer.bookManager.getBooksMetadata(
            request: .init(library: mockCalibreBook.library, books: [123], getAnnotations: false))
        XCTAssertEqual(result[123], .failed("The server could not refresh book details (HTTP 503). Please try again."))
    }

    func testAnnotationFailureKeepsSuccessfullyCommittedBookMetadata() async throws {
        var book = try makeDownloadReadBook()
        book.inShelf = true
        book.formats["EPUB"]?.cached = true
        mockAppContainer.bookManager.updateBook(book: book)
        configureMetadataResponse(body: "{}")
        let log = MockURLProtocol.answer(["/ajax/books/lib1": #"{"123":\#(try metadataJSON(title: "Saved despite failed annotations"))}"#])

        let result = await mockAppContainer.bookManager.getBooksMetadata(
            request: .init(library: book.library, books: [book.id], getAnnotations: true))

        XCTAssertEqual(result[book.id], .updated)
        XCTAssertEqual(mockAppContainer.bookManager.booksInShelf[book.inShelfId]?.title, "Saved despite failed annotations")
        XCTAssertEqual(mockAppContainer.bookRepository.getBook(id: book.inShelfId)?.title, "Saved despite failed annotations")
        XCTAssertEqual(log.unexpected, ["/book-get-annotations/lib1/123-EPUB"])
        XCTAssertFalse(mockAppContainer.librarySyncStatus[book.library.id]?.err.contains(book.id) ?? false)
    }

    func testFailedMetadataCommitPublishesNoSuccessAndKeepsOldShelf() async throws {
        let book = try makeDownloadReadBook()
        configureMetadataResponse(body: #"{"123":\#(try metadataJSON(title: "Uncommitted title"))}"#)
        let repository = PausingMetadataBookRepository(databaseService: mockAppContainer.databaseService,
            libraryResolver: mockAppContainer)
        repository.failCommit = true
        let manager = CalibreBookManager(container: mockAppContainer,
            databaseService: mockAppContainer.databaseService, bookRepository: repository)
        var shelved = book
        shelved.inShelf = true
        manager.updateBook(book: shelved)
        mockAppContainer.librarySyncStatus[book.library.id] = .init(library: book.library, del: [book.id])
        let stream = mockAppContainer.calibreUpdates()
        let notifications = Task { @MainActor in
            var updated = [String]()
            for await event in stream {
                if case .book(let snapshot) = event { updated.append(snapshot.title) }
                if case .shelf = event { return updated }
            }
            return updated
        }
        let results = await manager.getBooksMetadata(
            request: .init(library: book.library, books: [book.id], getAnnotations: false))
        mockAppContainer.publishCalibreUpdate(.shelf)
        let updated = await notifications.value

        XCTAssertEqual(results[book.id], .failed("Could not save book details. Please try again."))
        XCTAssertTrue(updated.isEmpty)
        XCTAssertEqual(mockAppContainer.librarySyncStatus[book.library.id]?.del, [book.id])
        XCTAssertEqual(manager.booksInShelf[book.inShelfId]?.title, book.title)
        XCTAssertEqual(repository.getBook(id: book.inShelfId)?.title, book.title)
    }

    func testQueuedMetadataWriteCannotSurviveDatabaseSwitchAwayAndBack() async throws {
        let book = try makeDownloadReadBook()
        let database = mockAppContainer.databaseService
        let original = try XCTUnwrap(database.realm)
        configureMetadataResponse(body: #"{"123":\#(try metadataJSON(title: "Retired request"))}"#)
        let queued = expectation(description: "Write work entered metadata queue")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let repository = PausingMetadataBookRepository(databaseService: database, libraryResolver: mockAppContainer)
        repository.atBoundary = {
            queued.fulfill()
            _ = release.wait(timeout: .now() + 10)
        }
        let manager = CalibreBookManager(container: mockAppContainer, databaseService: database, bookRepository: repository)
        let refresh = Task { await manager.getBooksMetadata(
            request: .init(library: book.library, books: [book.id], getAnnotations: false)) }
        await fulfillment(of: [queued], timeout: 10)
        try database.openMainRealm(conf: .init(inMemoryIdentifier: UUID().uuidString, schemaVersion: DatabaseSchema.version))
        try database.openMainRealm(conf: original.configuration)
        release.signal()

        let result = await refresh.value
        XCTAssertEqual(result[book.id], .superseded)
        database.refreshMainRealm()
        XCTAssertEqual(repository.getBook(id: book.inShelfId)?.title, book.title)
        withExtendedLifetime(original) {}
    }

    private func metadataJSON(title: String) throws -> String {
        var entry = CalibreBookEntry()
        entry.title = title
        entry.last_modified = "2026-11-14T00:00:00.123456Z"
        return String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
    }

    func testManagerReturnsCancelledForCancelledRequest() async throws {
        let request = CalibreBooksMetadataRequest(library: mockCalibreBook.library, books: [123], getAnnotations: false)
        let manager = mockAppContainer.bookManager
        let task = Task { await manager.getBooksMetadata(request: request) }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result[123], .cancelled)
    }

    func testViewModelSetup() throws {
        XCTAssertEqual(viewModel.calibreBook?.id, 123)
        XCTAssertEqual(viewModel.calibreBook?.title, "Test Book")
    }

    func testSetupObservesBookValueTypeUpdates() async throws {
        let expectation = expectation(description: "book stream update propagates to view model")
        viewModel.$calibreBook
            .compactMap { $0?.title }
            .dropFirst()
            .sink { title in
                if title == "Updated Book" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        try await Task.sleep(nanoseconds: 50_000_000)
        try mockAppContainer.databaseService.realm!.write {
            mockBookRealm.title = "Updated Book"
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(viewModel.calibreBook?.title, "Updated Book")
    }
    
    func testReadBookWhenNotInShelf() throws {
        mockCalibreBook.inShelf = false
        viewModel.readBook(book: mockCalibreBook)
        XCTAssertNotNil(viewModel.alertItem, "Alert item should be set if there is no format to download")
    }
    
    func testReadBookWhenInShelf() throws {
        mockCalibreBook.inShelf = true
        mockCalibreBook.formats[Format.EPUB.rawValue] = FormatInfo(
            selected: true,
            filename: "detail-test.epub",
            serverSize: 1024,
            serverMTime: Date(),
            cached: true,
            cacheSize: 1024,
            cacheMTime: Date(),
            manifest: nil
        )
        if let savedURL = getSavedUrl(book: mockCalibreBook, format: .EPUB) {
            try FileManager.default.createDirectory(
                at: savedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            FileManager.default.createFile(atPath: savedURL.path, contents: Data("EPUB".utf8))
        }

        viewModel.readBook(book: mockCalibreBook)
        let presentation = mockAppContainer.sessionManager.activeReaderPresentation
        XCTAssertNotNil(presentation, "Reader presentation should be created when reading an in-shelf book")
        XCTAssertEqual(presentation?.book.inShelfId, mockCalibreBook.inShelfId, "Reader presentation should target the selected detail book")
        XCTAssertEqual(presentation?.source, .bookDetail)
    }

    func testDownloadAndReadOpensOnceInTheOriginatingWorkspace() async throws {
        var book = try XCTUnwrap(mockCalibreBook)
        book.formats = ["EPUB": FormatInfo(selected: true, filename: "download-read.epub", serverSize: 1024,
            serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: .distantPast, manifest: nil)]
        mockAppContainer.bookRepository.saveBook(book)
        let savedURL = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try? FileManager.default.removeItem(at: savedURL)
        defer { try? FileManager.default.removeItem(at: savedURL) }
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost/get/EPUB/123/lib1"))
        let task = DetailDownloadTask(url: sourceURL)
        let download = BookFormatDownload(isDownloading: true, book: book, format: .EPUB,
            startDatetime: Date(), sourceURL: sourceURL, savedURL: savedURL,
            modificationDate: Date(), downloadTask: task)
        mockAppContainer.downloadManager.activeDownloads[sourceURL] = download
        let workspaceID = UUID()
        viewModel.targetWorkspaceID = workspaceID
        var requests = [ReaderOpenRequest]()
        let stream = mockAppContainer.readerOpenRequests()
        let observer = Task { @MainActor in
            for await request in stream { requests.append(request) }
        }
        defer { observer.cancel() }
        await Task.yield()

        viewModel.readBook(book: book)
        viewModel.readBook(book: book)
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        // A later workspace focus change must not redirect the original read request.
        viewModel.targetWorkspaceID = UUID()
        let delegate = BookFormatDownloadDelegate(download: download, manager: mockAppContainer.downloadManager)
        try stageReadDownload(download, task: task, delegate: delegate)
        delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
        await waitUntil { !requests.isEmpty }

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.targetWorkspaceID, workspaceID)
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.book.inShelfId, book.inShelfId)
        delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
        await Task.yield()
        XCTAssertEqual(requests.count, 1)
    }

    func testReadStartsThePreferredSupportedFormatAndIgnoresUnsupportedSelection() throws {
        var book = try makeDownloadReadBook()
        book.formats["UNKNOWN"] = book.formats["EPUB"]
        book.formats["UNKNOWN"]?.selected = true
        book.formats["PDF"] = book.formats["EPUB"]
        book.formats["PDF"]?.selected = true
        book.formats["EPUB"]?.selected = false
        viewModel.readBook(book: book)
        let download = try XCTUnwrap(mockAppContainer.downloadManager.activeDownloads.values.first)
        XCTAssertEqual(download.format, .PDF)
        XCTAssertTrue(viewModel.isWaitingToRead(book))
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        viewModel.cancelDownload(book: book, format: .PDF)
    }

    func testCachedReadKeepsTheExistingPositionAndDoesNotDownload() throws {
        var book = try makeDownloadReadBook()
        book.inShelf = true
        book.formats["EPUB"]?.cached = true
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try Data("EPUB".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let position = BookDeviceReadingPosition(id: mockAppContainer.deviceName,
            readerName: ReaderType.ReadiumEPUB.rawValue, lastReadPage: 12, lastProgress: 42,
            epoch: Date().timeIntervalSince1970)
        mockAppContainer.readingPositionRepository.savePosition(position, for: book)
        mockAppContainer.bookRepository.saveBook(book)
        viewModel.setup(bookId: book.inShelfId)
        XCTAssertEqual(viewModel.readActionTitle(for: book), "Read")
        viewModel.readBook(book: book)
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.readerInfo.position.lastReadPage, 12)
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.readerInfo.readerType, .ReadiumEPUB)
        XCTAssertTrue(mockAppContainer.downloadManager.activeDownloads.isEmpty)
    }

    func testDownloadOnlyCompletesWithoutOpeningReader() async throws {
        let book = try makeDownloadReadBook()
        XCTAssertEqual(viewModel.readActionTitle(for: book), "Download and Read")
        viewModel.downloadOnly(book: book)
        let download = try controlledDownload(for: book)
        XCTAssertFalse(viewModel.isWaitingToRead(book))
        try await completeReadDownload(download)
        await waitUntil { self.mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion != nil }
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        let cached = try XCTUnwrap(mockAppContainer.bookRepository.getBook(id: book.inShelfId))
        await waitUntil { self.viewModel.canRead(cached) }
        XCTAssertEqual(viewModel.readActionTitle(for: cached), "Read")
    }

    func testFormatDownloadOnlyDoesNotOpenReader() async throws {
        let book = try makeDownloadReadBook()
        viewModel.cacheFormat(book: book, format: .EPUB)
        let download = try controlledDownload(for: book)
        try await completeReadDownload(download)
        await waitUntil { self.mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion != nil }
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testFailureAllowsRetryAndLateOldCompletionCannotOpen() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let first = try controlledDownload(for: book)
        let failed = BookFormatDownloadDelegate(download: first, manager: mockAppContainer.downloadManager)
        failed.urlSession(URLSession.shared, task: try XCTUnwrap(first.downloadTask),
            didCompleteWithError: URLError(.notConnectedToInternet))
        await waitUntil { !self.viewModel.isWaitingToRead(book) }
        XCTAssertNotNil(viewModel.alertItem)
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        let updatedBook = try XCTUnwrap(mockAppContainer.bookRepository.getBook(id: book.inShelfId))
        viewModel.readBook(book: updatedBook)
        let second = try controlledDownload(for: book)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(viewModel.alertItem)
        try stageReadDownload(first, task: XCTUnwrap(first.downloadTask), delegate: failed)
        failed.urlSession(URLSession.shared, task: try XCTUnwrap(first.downloadTask), didCompleteWithError: nil)
        await Task.yield()
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        try await completeReadDownload(second)
        await waitUntil { self.mockAppContainer.sessionManager.activeReaderPresentation != nil }
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.book.inShelfId, book.inShelfId)
    }

    func testCancelAllowsRetryAndIgnoresLateSuccessfulCallback() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let first = try controlledDownload(for: book)
        viewModel.cancelReadDownload(book: book)
        XCTAssertFalse(viewModel.isWaitingToRead(book))
        try await completeReadDownload(first)
        await Task.yield()
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        XCTAssertEqual(mockAppContainer.downloadManager.activeDownloads[first.sourceURL]?.completion, .cancelled)
        let savedURL = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try? FileManager.default.removeItem(at: savedURL)
        viewModel.readBook(book: try XCTUnwrap(mockAppContainer.bookRepository.getBook(id: book.inShelfId)))
        let retry = try controlledDownload(for: book)
        XCTAssertNotEqual(first.id, retry.id)
        try await completeReadDownload(retry)
        await waitUntil { self.mockAppContainer.sessionManager.activeReaderPresentation != nil }
        XCTAssertNotNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testLeavingDetailDiscardsAutoReadUntilAnotherExplicitRead() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        viewModel.onDisappear()
        try await completeReadDownload(download)
        await waitUntil { self.mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion != nil }
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        XCTAssertTrue(viewModel.setup(bookId: book.inShelfId))
        await Task.yield()
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        viewModel.readBook(book: try XCTUnwrap(mockAppContainer.bookRepository.getBook(id: book.inShelfId)))
        XCTAssertNotNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testOpeningHistoryDiscardsAutoRead() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        viewModel.showReadingPositionHistory(book: book)
        try await completeReadDownload(download)
        await waitUntil { self.mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion != nil }
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testAnotherReaderOpeningDiscardsPendingAutoRead() async throws {
        let book = try makeDownloadReadBook()
        await Task.yield()
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        mockAppContainer.publishDismissAll("reader-opened")
        await waitUntil { !self.viewModel.isWaitingToRead(book) }
        try await completeReadDownload(download)
        await waitUntil { self.mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion != nil }
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testSameNumericBookIDInAnotherLibraryCannotOpenOrBlockThisBook() async throws {
        let book = try makeDownloadReadBook()
        let otherLibrary = CalibreLibrary(server: book.library.server, key: "other", name: "Other")
        var other = CalibreBook(id: book.id, library: otherLibrary)
        other.formats = book.formats
        viewModel.cacheFormat(book: other, format: .EPUB)
        let otherDownload = try controlledDownload(for: other)
        defer { try? FileManager.default.removeItem(at: otherDownload.savedURL) }
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        viewModel.cancelDownload(book: other, format: .EPUB)
        XCTAssertTrue(mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.isActive == true)
        XCTAssertTrue(viewModel.isWaitingToRead(book))
        try await completeReadDownload(otherDownload)
        await Task.yield()
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        try await completeReadDownload(download)
        await waitUntil { self.mockAppContainer.sessionManager.activeReaderPresentation != nil }
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.book.inShelfId, book.inShelfId)
    }

    func testCompletionWithoutStagedFileDoesNotOpenAndAllowsRetry() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        let delegate = BookFormatDownloadDelegate(download: download, manager: mockAppContainer.downloadManager)
        delegate.urlSession(URLSession.shared, task: try XCTUnwrap(download.downloadTask), didCompleteWithError: nil)
        await waitUntil { !self.viewModel.isWaitingToRead(book) }
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        XCTAssertNotNil(viewModel.alertItem)
        viewModel.readBook(book: try XCTUnwrap(mockAppContainer.bookRepository.getBook(id: book.inShelfId)))
        XCTAssertTrue(viewModel.isWaitingToRead(book))
        viewModel.cancelReadDownload(book: book)
    }

    func testDownloadAndReadPDFUsesTheAvailablePDFReader() async throws {
        try await assertDownloadAndRead(format: .PDF)
    }

    func testDownloadAndReadCBZUsesReadium() async throws {
        try await assertDownloadAndRead(format: .CBZ)
    }

    func testPauseAndResumeRetainsThePendingRead() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let first = try controlledDownload(for: book)
        viewModel.pauseDownload(book: book, format: .EPUB)
        await Task.yield()
        XCTAssertTrue(viewModel.isWaitingToRead(book))
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        viewModel.resumeDownload(book: book, format: .EPUB)
        let resumed = try controlledDownload(for: book)
        XCTAssertEqual(resumed.id, first.id)
        try await completeReadDownload(resumed)
        await waitUntil { self.mockAppContainer.sessionManager.activeReaderPresentation != nil }
        XCTAssertNotNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    private func assertDownloadAndRead(format: Format) async throws {
        var book = try makeDownloadReadBook()
        let info = try XCTUnwrap(book.formats["EPUB"])
        book.formats = [format.rawValue: info]
        mockAppContainer.bookRepository.saveBook(book)
        let url = try XCTUnwrap(getSavedUrl(book: book, format: format))
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        XCTAssertEqual(download.format, format)
        try await completeReadDownload(download)
        await waitUntil { self.mockAppContainer.sessionManager.activeReaderPresentation != nil }
        let presentation = try XCTUnwrap(mockAppContainer.sessionManager.activeReaderPresentation)
        XCTAssertEqual(presentation.readerInfo.format, format)
        XCTAssertEqual(presentation.readerInfo.readerType, mockAppContainer.sessionManager.getPreferredReader(for: format))
    }

    func testFormatStatesSeparateFormatsAndLibrariesDuringPauseAndCancel() async throws {
        var book = try makeDownloadReadBook()
        book.formats["PDF"] = book.formats["EPUB"]
        book.formats["MOBI"] = book.formats["EPUB"]
        mockAppContainer.bookRepository.saveBook(book)
        viewModel.setup(bookId: book.inShelfId)
        viewModel.cacheFormat(book: book, format: .EPUB)
        _ = try controlledDownload(for: book)
        viewModel.pauseDownload(book: book, format: .EPUB)
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "EPUB" }?.transferText, "Pausing…")
        await waitUntil { self.viewModel.formatStates.first { $0.id == "EPUB" }?.transferText == "Paused" }
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "EPUB" }?.transferText, "Paused")
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "PDF" }?.canDownload, true)
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "MOBI" }?.canDownload, false)
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "MOBI" }?.canPreview, false)
        let otherLibrary = TestFixtures.makeLibrary(server: book.library.server, key: "other", name: "Other")
        var other = CalibreBook(id: book.id, library: otherLibrary)
        other.formats = book.formats
        try mockAppContainer.libraryManager.saveLibrary(library: otherLibrary)
        mockAppContainer.bookRepository.saveBook(other)
        viewModel.cacheFormat(book: other, format: .PDF)
        let otherDownload = try controlledDownload(for: other)
        viewModel.cancelDownload(book: book, format: .EPUB)
        XCTAssertFalse(viewModel.isFormatDownloading(book: book, format: .EPUB))
        XCTAssertTrue(viewModel.isFormatDownloading(book: other, format: .PDF))
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "PDF" }?.isTransferring, false)
        mockAppContainer.downloadManager.cancelDownload(other, format: otherDownload.format)
    }

    func testMissingFileSnapshotDisablesPreviewAndAllowsRedownload() throws {
        var book = try makeDownloadReadBook()
        book.formats["EPUB"]?.cached = true
        mockAppContainer.bookRepository.saveBook(book)
        viewModel.setup(bookId: book.inShelfId)
        let state = try XCTUnwrap(viewModel.formatStates.first)
        XCTAssertEqual(state.statusText, "File missing. Download again.")
        XCTAssertFalse(state.canPreview)
        XCTAssertTrue(state.canDownload)
        XCTAssertFalse(viewModel.canRead(book))
    }

    func testLocalOriginalCannotBeClearedOrDownloaded() throws {
        let server = TestFixtures.makeServer(name: "Local Original", baseUrl: ".")
        let library = TestFixtures.makeLibrary(server: server, key: "BD3-Local", name: "BD3 Local")
        try mockAppContainer.serverRepository.saveServer(server)
        mockAppContainer.calibreServers[server.id] = server
        try mockAppContainer.libraryRepository.saveLibrary(library)
        mockAppContainer.calibreLibraries[library.id] = library
        var book = CalibreBook(id: 123, library: library)
        book.inShelf = true
        book.formats["EPUB"] = FormatInfo(filename: "original.epub", serverSize: 4,
            serverMTime: Date(), cached: true, cacheSize: 4, cacheMTime: Date())
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("EPUB".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        mockAppContainer.bookRepository.saveBook(book)
        viewModel.setup(bookId: book.inShelfId)
        let state = try XCTUnwrap(viewModel.formatStates.first)
        XCTAssertTrue(state.canPreview)
        XCTAssertFalse(state.canClear)
        XCTAssertFalse(state.canDownload)
        viewModel.clearFormat(book: book, format: .EPUB)
        viewModel.cacheFormat(book: book, format: .EPUB)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(viewModel.getActiveDownload(book: book, format: .EPUB))
    }

    func testClearOneFormatPreservesOtherFileAndReadingPosition() throws {
        var book = try makeDownloadReadBook()
        book.inShelf = true
        book.formats["PDF"] = book.formats["EPUB"]
        for format in [Format.EPUB, .PDF] {
            let url = try XCTUnwrap(getSavedUrl(book: book, format: format))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(format.rawValue.utf8).write(to: url)
            book.formats[format.rawValue]?.cached = true
        }
        let epubURL = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        let pdfURL = try XCTUnwrap(getSavedUrl(book: book, format: .PDF))
        defer { try? FileManager.default.removeItem(at: epubURL); try? FileManager.default.removeItem(at: pdfURL) }
        mockAppContainer.bookManager.addToShelf(book: book, formats: [.EPUB, .PDF])
        var position = mockAppContainer.readingPositionRepository.createInitial(deviceName: mockAppContainer.deviceName, reader: .YabrEPUB)
        position.lastReadPage = 27
        mockAppContainer.readingPositionRepository.savePosition(position, for: book)
        viewModel.setup(bookId: book.inShelfId)
        viewModel.clearFormat(book: book, format: .PDF)
        XCTAssertTrue(FileManager.default.fileExists(atPath: epubURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfURL.path))
        XCTAssertEqual(mockAppContainer.readingPositionRepository.getPosition(for: book, policy: .latest)?.lastReadPage, 27)
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "EPUB" }?.canPreview, true)
        XCTAssertEqual(viewModel.formatStates.first { $0.id == "PDF" }?.canPreview, false)
    }

    func testPreviewReaderCallbacksCannotOverwritePositionForAnyEngine() throws {
        let book = try XCTUnwrap(mockCalibreBook)
        var original = mockAppContainer.readingPositionRepository.createInitial(deviceName: mockAppContainer.deviceName, reader: .YabrEPUB)
        original.lastReadPage = 27
        mockAppContainer.readingPositionRepository.savePosition(original, for: book)
        for reader in ReaderType.allCases where reader != .UNSUPPORTED {
            let bridge = YabrEBookReaderRepresentable(book: book,
                readerInfo: ReaderInfo(deviceName: mockAppContainer.deviceName, url: URL(fileURLWithPath: "/preview.\(reader.format.ext)"),
                    missing: false, format: reader.format, readerType: reader, position: original), isPreview: true)
            bridge.makeCoordinator().readerEngine(NSObject(), didUpdatePosition: ReaderEnginePosition(pageNumber: 99, maxPage: 100))
            XCTAssertEqual(mockAppContainer.readingPositionRepository.getPosition(for: book, policy: .latest)?.lastReadPage, 27)
        }
    }

    func testCompletingTwoFormatsPreservesBothCachesAndCurrentMetadata() async throws {
        var book = try makeDownloadReadBook()
        book.formats["PDF"] = book.formats["EPUB"]
        mockAppContainer.bookRepository.saveBook(book)
        viewModel.cacheFormat(book: book, format: .EPUB)
        let epub = try controlledDownload(for: book, format: .EPUB)
        viewModel.cacheFormat(book: book, format: .PDF)
        let pdf = try controlledDownload(for: book, format: .PDF)
        defer { try? FileManager.default.removeItem(at: epub.savedURL); try? FileManager.default.removeItem(at: pdf.savedURL) }
        var refreshed = try XCTUnwrap(mockAppContainer.bookRepository.getBook(id: book.inShelfId))
        refreshed.title = "Refreshed During Download"
        mockAppContainer.bookRepository.saveBook(refreshed)
        try await completeReadDownload(epub)
        try await completeReadDownload(pdf)
        let saved = try XCTUnwrap(mockAppContainer.bookRepository.getBook(id: book.inShelfId))
        XCTAssertEqual(saved.title, "Refreshed During Download")
        XCTAssertEqual(saved.formats["EPUB"]?.cached, true)
        XCTAssertEqual(saved.formats["PDF"]?.cached, true)
        XCTAssertEqual(saved.formats["EPUB"]?.selected, true)
        XCTAssertEqual(saved.formats["PDF"]?.selected, true)
    }

    private func makeDownloadReadBook() throws -> CalibreBook {
        var book = try XCTUnwrap(mockCalibreBook)
        book.formats = ["EPUB": FormatInfo(selected: nil, filename: "download-read.epub", serverSize: 1024,
            serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: .distantPast, manifest: nil)]
        mockAppContainer.bookRepository.saveBook(book)
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DetailHoldingURLProtocol.self]
        mockAppContainer.downloadManager.sessionConfiguration = configuration
        return book
    }

    /// Keep the real startDownload path; replace only its transport for deterministic callbacks.
    private func controlledDownload(for book: CalibreBook, format: Format? = nil) throws -> BookFormatDownload {
        let manager = mockAppContainer.downloadManager
        var download = try XCTUnwrap(manager.activeDownloads.values.first { $0.book.inShelfId == book.inShelfId && $0.isActive && (format == nil || $0.format == format) })
        let originalTask = download.downloadTask
        download.downloadTask = DetailDownloadTask(url: download.sourceURL)
        manager.activeDownloads[download.sourceURL] = download
        originalTask?.cancel()
        return download
    }

    private func stageReadDownload(_ download: BookFormatDownload, task: URLSessionDownloadTask,
                                   delegate: BookFormatDownloadDelegate) throws {
        let directory = download.savedURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data("EPUB".utf8).write(to: temporary)
        delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: temporary)
    }

    private func completeReadDownload(_ download: BookFormatDownload) async throws {
        let task = try XCTUnwrap(download.downloadTask)
        let delegate = BookFormatDownloadDelegate(download: download, manager: mockAppContainer.downloadManager)
        try stageReadDownload(download, task: task, delegate: delegate)
        delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
        await Task.yield()
        await waitUntil { self.mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion != nil }
        XCTAssertNotNil(mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion)
        withExtendedLifetime(delegate) {}
    }
    
    func testParseManifestToTOCSuccess() {
        let data = Data("{\"toc\": {\"children\": [{\"title\": \"Chapter 1\"}, {\"title\": \"Chapter 2\"}]}}".utf8)
        XCTAssertEqual(BookPreviewViewModel.parseManifest(data), .loaded("Chapter 1\nChapter 2\n"))
    }

    func testParseManifestToTOCWaiting() {
        XCTAssertEqual(BookPreviewViewModel.parseManifest(Data("{\"job_status\": \"waiting\"}".utf8)), .generating)
    }

    func testParseManifestToTOCInvalidJSON() {
        guard case .failed = BookPreviewViewModel.parseManifest(Data("Invalid JSON".utf8)) else {
            return XCTFail("Invalid payload must be a recoverable failure")
        }
    }

    func testUpdatingMetadata() throws {
        XCTAssertFalse(viewModel.updatingMetadata)
        mockAppContainer.updatingMetadata = true
        mockAppContainer.updatingMetadataStatus = "another book failed"
        XCTAssertFalse(viewModel.updatingMetadata)
        XCTAssertEqual(viewModel.refreshState, .idle)
    }

    private func setupMockGoodreadsSync(dateReadColumn: String = "#date_read", readingProgressColumn: String = "#progress") {
        let options = CalibreDSReaderHelperPrefs.Options(
            servicePort: 8080,
            goodreadsSyncEnabled: true,
            dictViewerEnabled: false,
            dictViewerLibraryName: "",
            readingPositionColumnAllLibrary: false,
            readingPositionColumnName: "",
            readingPositionColumnPrefix: "",
            readingPositionColumnUserSeparated: false
        )
        let dsPrefs = CalibreDSReaderHelperPrefs(plugin_prefs: .init(Options: options))
        
        let grSync = CalibreGoodreadsSyncPrefs.Goodreads(
            dateReadColumn: dateReadColumn,
            ratingColumn: "#rating",
            readingProgressColumn: readingProgressColumn,
            reviewTextColumn: "#review",
            tagMappingColumn: "#tags"
        )
        let grUsers = ["Default": CalibreGoodreadsSyncPrefs.Shelves(shelves: [])]
        let grPluginPrefs = CalibreGoodreadsSyncPrefs.PluginPrefs(
            SchemaVersion: 1.0,
            Goodreads: grSync,
            Users: grUsers
        )
        let grPrefs = CalibreGoodreadsSyncPrefs(plugin_prefs: grPluginPrefs)
        
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: dsPrefs,
            count_pages_prefs: nil,
            goodreads_sync_prefs: grPrefs
        )
        
        var helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        
        guard let library = mockCalibreBook?.library else { return }
        
        try! mockAppContainer.databaseService.realm!.write {
            if let serverRealm = mockAppContainer.databaseService.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = CalibreServerDSReaderHelperRealm(value: helper)
            }
        }
    }
    
    func testReadingProgressSummary_GoodreadsReadDate() throws {
        setupMockGoodreadsSync(dateReadColumn: "#date_read")
        mockCalibreBook.userMetadatas = ["date_read": "2026-06-21T15:00:00Z"]
        
        let expectedDate = ISO8601DateFormatter().date(from: "2026-06-21T15:00:00Z")!
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.autoupdatingCurrent
        let expectedString = dateFormatter.string(from: expectedDate)
        
        mockAppContainer.bookRepository.saveBook(mockCalibreBook)
        viewModel.setup(bookId: mockCalibreBook.inShelfId)
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .goodreadsReadDate(expectedString))
    }
    
    func testReadingProgressSummary_GoodreadsProgress() throws {
        setupMockGoodreadsSync(readingProgressColumn: "#progress")
        mockCalibreBook.userMetadatas = ["progress": 85]
        
        mockAppContainer.bookRepository.saveBook(mockCalibreBook)
        viewModel.setup(bookId: mockCalibreBook.inShelfId)
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .goodreadsProgress("85"))
    }
    
    func testReadingProgressSummary_LocalProgress_CurrentDevice() throws {
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: nil,
            count_pages_prefs: nil,
            goodreads_sync_prefs: nil
        )
        var helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        guard let library = mockAppContainer.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockAppContainer.databaseService.realm!.write {
            if let serverRealm = mockAppContainer.databaseService.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = CalibreServerDSReaderHelperRealm(value: helper)
            }
        }
        
        let devicePosition = BookDeviceReadingPosition(
            id: viewModel.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 12,
            lastProgress: 75.0,
            epoch: Date().timeIntervalSince1970
        )
        mockAppContainer.readingPositionRepository.savePosition(devicePosition, for: mockCalibreBook)
        
        let otherPosition = BookDeviceReadingPosition(
            id: "other-device",
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 5,
            lastProgress: 30.0,
            epoch: Date().timeIntervalSince1970
        )
        mockAppContainer.readingPositionRepository.savePosition(otherPosition, for: mockCalibreBook)
        
        mockAppContainer.bookRepository.saveBook(mockCalibreBook)
        viewModel.setup(bookId: mockCalibreBook.inShelfId)
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .localProgress(percent: 75.0, device: viewModel.deviceName))
    }
    
    func testReadingProgressSummary_LocalProgress_Fallback() throws {
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: nil,
            count_pages_prefs: nil,
            goodreads_sync_prefs: nil
        )
        var helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        guard let library = mockAppContainer.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockAppContainer.databaseService.realm!.write {
            if let serverRealm = mockAppContainer.databaseService.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = CalibreServerDSReaderHelperRealm(value: helper)
            }
        }
        
        let otherPosition = BookDeviceReadingPosition(
            id: "other-device",
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 5,
            lastProgress: 30.0,
            epoch: Date().timeIntervalSince1970
        )
        mockAppContainer.readingPositionRepository.savePosition(otherPosition, for: mockCalibreBook)
        
        mockAppContainer.bookRepository.saveBook(mockCalibreBook)
        viewModel.setup(bookId: mockCalibreBook.inShelfId)
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .localProgress(percent: 30.0, device: "other-device"))
    }
    
    func testReadingProgressSummary_None() throws {
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: nil,
            count_pages_prefs: nil,
            goodreads_sync_prefs: nil
        )
        var helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        guard let library = mockAppContainer.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockAppContainer.databaseService.realm!.write {
            if let serverRealm = mockAppContainer.databaseService.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = CalibreServerDSReaderHelperRealm(value: helper)
            }
        }
        
        mockAppContainer.bookRepository.saveBook(mockCalibreBook)
        viewModel.setup(bookId: mockCalibreBook.inShelfId)
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertNil(summary)
    }
    
    func testShowReadingPositionHistoryPushesHistory() throws {
        XCTAssertFalse(viewModel.isReadingPositionHistoryActive)

        viewModel.showReadingPositionHistory(book: mockCalibreBook)

        XCTAssertTrue(viewModel.isReadingPositionHistoryActive)
        XCTAssertEqual(viewModel.readingHistoryViewModel?.library.id, mockCalibreBook.library.id)
        XCTAssertEqual(viewModel.readingHistoryViewModel?.bookId, mockCalibreBook.id)
    }

    func testReaderDismissesActivityEvenAfterDetailStopsObserving() async {
        viewModel.showActivity(book: mockCalibreBook)
        XCTAssertNotNil(viewModel.activityViewModel)
        viewModel.onDisappear()

        mockAppContainer.publishDismissAll("reader-opened")

        await waitUntil { self.viewModel.activityViewModel == nil }
        XCTAssertNil(viewModel.activityViewModel)
    }

    func testOnAppearSkipsNetworkRefreshOnlyWhenReturningFromHistory() async throws {
        let workspaceID = UUID()
        let bookId = try XCTUnwrap(mockBookRealm.primaryKey)
        var refreshCount = 0
        let realm = try XCTUnwrap(mockAppContainer.databaseService.realm)
        let detailViewModel = BookDetailViewModel(container: mockAppContainer, refreshMetadata: { request in
            refreshCount += 1
            return [request.books[0]: .updated]
        })
        detailViewModel.onAppear(bookId: bookId, targetWorkspaceID: workspaceID)
        await waitUntil { refreshCount == 1 }
        let book = try XCTUnwrap(detailViewModel.calibreBook)
        detailViewModel.showReadingPositionHistory(book: book)
        detailViewModel.onDisappear()
        try realm.write { mockBookRealm.title = "Edited In History" }
        detailViewModel.onAppear(bookId: bookId, targetWorkspaceID: workspaceID)
        XCTAssertEqual(detailViewModel.calibreBook?.title, "Edited In History")
        XCTAssertEqual(detailViewModel.targetWorkspaceID, workspaceID)
        await Task.yield()
        XCTAssertEqual(refreshCount, 1)
        try realm.write { mockBookRealm.title = "Observed After Return" }
        await waitUntil { detailViewModel.calibreBook?.title == "Observed After Return" }
        XCTAssertEqual(detailViewModel.calibreBook?.title, "Observed After Return")
        XCTAssertEqual(refreshCount, 1)
        detailViewModel.onDisappear()
        detailViewModel.onAppear(bookId: bookId, targetWorkspaceID: workspaceID)
        await waitUntil { refreshCount == 2 }
        XCTAssertEqual(refreshCount, 2)
        detailViewModel.onDisappear()
    }

    func testHasReadingHistory() throws {
        XCTAssertFalse(viewModel.hasReadingHistory(for: mockCalibreBook))
        
        let position = BookDeviceReadingPosition(
            id: "some-device",
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 5,
            lastProgress: 30.0,
            epoch: Date().timeIntervalSince1970
        )
        mockAppContainer.readingPositionRepository.savePosition(position, for: mockCalibreBook)
        
        viewModel.setup(bookId: mockCalibreBook.inShelfId)
        XCTAssertTrue(viewModel.hasReadingHistory(for: mockCalibreBook))
    }
    
    func testIsFormatDownloading() throws {
        let format = Format.EPUB
        XCTAssertFalse(viewModel.isFormatDownloading(book: mockCalibreBook, format: format))
        
        let download = BookFormatDownload(
            isDownloading: true,
            progress: 0.5,
            resumeData: nil,
            book: mockCalibreBook,
            format: format,
            startDatetime: Date(),
            sourceURL: URL(string: "http://localhost")!,
            savedURL: URL(string: "file:///local")!,
            modificationDate: Date()
        )
        viewModel.activeDownloads[download.savedURL] = download
        XCTAssertTrue(viewModel.isFormatDownloading(book: mockCalibreBook, format: format))
        XCTAssertFalse(viewModel.isFormatDownloading(book: CalibreBook(id: 456, library: mockCalibreBook.library), format: format))

        let pausedDownload = BookFormatDownload(
            isDownloading: false,
            isPaused: true,
            progress: 0.5,
            resumeData: nil,
            book: mockCalibreBook,
            format: format,
            startDatetime: Date(),
            sourceURL: URL(string: "http://localhost/paused")!,
            savedURL: URL(string: "file:///local-paused")!,
            modificationDate: Date()
        )
        viewModel.activeDownloads = [pausedDownload.savedURL: pausedDownload]
        XCTAssertTrue(viewModel.isFormatDownloading(book: mockCalibreBook, format: format))
        
        viewModel.activeDownloads.removeAll()
    }
    
    func testGetActiveDownload() throws {
        let format = Format.EPUB
        XCTAssertNil(viewModel.getActiveDownload(book: mockCalibreBook, format: format))
        
        let download = BookFormatDownload(
            isDownloading: true,
            progress: 0.5,
            resumeData: nil,
            book: mockCalibreBook,
            format: format,
            startDatetime: Date(),
            sourceURL: URL(string: "http://localhost")!,
            savedURL: URL(string: "file:///local")!,
            modificationDate: Date()
        )
        viewModel.activeDownloads[download.savedURL] = download
        
        let retrieved = viewModel.getActiveDownload(book: mockCalibreBook, format: format)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.book.id, 123)
        XCTAssertEqual(retrieved?.format, format)

        let pausedDownload = BookFormatDownload(
            isDownloading: false,
            isPaused: true,
            progress: 0.5,
            resumeData: nil,
            book: mockCalibreBook,
            format: format,
            startDatetime: Date(),
            sourceURL: URL(string: "http://localhost/paused")!,
            savedURL: URL(string: "file:///local-paused")!,
            modificationDate: Date()
        )
        viewModel.activeDownloads = [pausedDownload.savedURL: pausedDownload]
        let pausedRetrieved = viewModel.getActiveDownload(book: mockCalibreBook, format: format)
        XCTAssertNotNil(pausedRetrieved)
        XCTAssertEqual(pausedRetrieved?.isPaused, true)
        
        viewModel.activeDownloads.removeAll()
    }
    
    func testFormatSnapshotUsesActiveAttemptThenNewestResultAcrossServerAddresses() async throws {
        let book = try makeDownloadReadBook()
        let savedURL = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        let originalURL = try XCTUnwrap(URL(string: "http://localhost/get/EPUB/123/lib1"))
        let changedURL = try XCTUnwrap(URL(string: "http://localhost:8080/get/EPUB/123/lib1"))
        var downloads = Dictionary(uniqueKeysWithValues: [originalURL, changedURL].map { url in
            (url, BookFormatDownload(completion: .failed("Connection failed"), book: book, format: .EPUB,
                startDatetime: .distantPast, sourceURL: url, savedURL: savedURL, modificationDate: .distantPast))
        })
        // Exercise the ordering that previously picked the failed record.
        let retryURL = try XCTUnwrap(Array(downloads.keys).last)
        downloads[retryURL]?.isDownloading = true
        downloads[retryURL]?.completion = nil
        downloads[retryURL]?.startDatetime = Date()
        let retryID = try XCTUnwrap(downloads[retryURL]?.id)
        mockAppContainer.downloadManager.activeDownloads = downloads
        viewModel.setup(bookId: book.inShelfId)
        defer { viewModel.onDisappear() }
        await waitUntil { self.viewModel.formatStates.first?.download != nil }

        let transferring = try XCTUnwrap(viewModel.formatStates.first)
        XCTAssertEqual(transferring.download?.id, retryID)
        XCTAssertTrue(transferring.isTransferring)
        XCTAssertFalse(transferring.canDownload)

        viewModel.cancelDownload(book: book, format: .EPUB)

        let cancelled = try XCTUnwrap(viewModel.formatStates.first)
        XCTAssertEqual(cancelled.download?.id, retryID)
        XCTAssertEqual(cancelled.download?.completion, .cancelled)
        XCTAssertTrue(cancelled.canDownload)
    }

    func testFormatSnapshotUsesCurrentFileAndServerFreshness() throws {
        var available = false
        let model = BookDetailViewModel(container: mockAppContainer, fileExists: { _ in available })
        var book = try XCTUnwrap(mockCalibreBook)
        book.formats["EPUB"] = FormatInfo(filename: "test.epub", serverSize: 100, serverMTime: Date(),
            cached: false, cacheSize: 0, cacheMTime: Date())
        mockAppContainer.bookRepository.saveBook(book)
        model.setup(bookId: book.inShelfId)
        XCTAssertEqual(model.formatStates.first?.statusText, "Not Downloaded")
        available = true
        book.formats["EPUB"]?.cached = true
        mockAppContainer.bookRepository.saveBook(book)
        model.setup(bookId: book.inShelfId)
        XCTAssertEqual(model.formatStates.first?.statusText, "Downloaded · Up to Date")
        book.formats["EPUB"]?.cacheMTime = .distantPast
        mockAppContainer.bookRepository.saveBook(book)
        model.setup(bookId: book.inShelfId)
        XCTAssertEqual(model.formatStates.first?.statusText, "Downloaded · Server Has Update")
        model.onDisappear()
    }

    func testDownloadInteraction() throws {
        var book = mockCalibreBook!
        book.formats = ["EPUB": FormatInfo(selected: nil, filename: "book.epub", serverSize: 1024, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)]
        
        XCTAssertFalse(viewModel.isFormatDownloading(book: book, format: .EPUB))
        viewModel.cacheFormat(book: book, format: .EPUB)
        
        viewModel.cancelDownload(book: book, format: .EPUB)
        XCTAssertFalse(viewModel.isFormatDownloading(book: book, format: .EPUB))
    }

    func testPreviewRejectsMissingCachedFile() throws {
        var book = try XCTUnwrap(mockCalibreBook)
        book.formats["EPUB"] = FormatInfo(filename: "missing-preview.epub", serverSize: 100,
            serverMTime: Date(), cached: true, cacheSize: 100, cacheMTime: Date())
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try? FileManager.default.removeItem(at: url)
        XCTAssertFalse(viewModel.previewAction(book: book, format: .EPUB,
            formatInfo: try XCTUnwrap(book.formats["EPUB"])))
        XCTAssertEqual(viewModel.alertItem?.id, "Cannot locate book file")
    }

    func testPreviewPreparationPreservesFormalReaderInfo() throws {
        var book = try XCTUnwrap(mockCalibreBook)
        book.formats["EPUB"] = FormatInfo(filename: "isolated-preview.epub", serverSize: 100,
            serverMTime: Date(), cached: true, cacheSize: 100, cacheMTime: Date())
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("EPUB".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var originalPosition = mockAppContainer.readingPositionRepository.createInitial(
            deviceName: mockAppContainer.deviceName, reader: .ReadiumPDF)
        originalPosition.lastReadPage = 42
        let originalURL = URL(fileURLWithPath: "/formal.pdf")
        mockAppContainer.sessionManager.prepareBookReading(url: originalURL, format: .PDF,
            readerType: .ReadiumPDF, position: originalPosition)
        XCTAssertTrue(viewModel.previewAction(book: book, format: .EPUB,
            formatInfo: try XCTUnwrap(book.formats["EPUB"])))
        XCTAssertEqual(mockAppContainer.sessionManager.readerInfo?.url, originalURL)
        XCTAssertEqual(mockAppContainer.sessionManager.readerInfo?.position.lastReadPage, 42)
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testPreviewSelection() async throws {
        var book = mockCalibreBook!
        book.formats = ["EPUB": FormatInfo(selected: nil, filename: "book.epub", serverSize: 1024, serverMTime: Date(), cached: true, cacheSize: 1024, cacheMTime: Date(), manifest: nil)]
        
        guard let savedURL = getSavedUrl(book: book, format: .EPUB) else {
            return XCTFail("Unable to get saved URL")
        }
        
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: savedURL.path, contents: Data("mock epubs".utf8))
        defer {
            try? fileManager.removeItem(at: savedURL)
        }
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        let calibreServerService = mockAppContainer.calibreServerService
        let library = book.library
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: library.server, timeout: timeout, qos: qos)
                calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let manifestJson = "{\"toc\": {\"children\": [{\"title\": \"Intro\"}]}}"
            return (response, manifestJson.data(using: .utf8)!)
        }
        
        let handled = viewModel.previewAction(book: book, format: .EPUB, formatInfo: book.formats["EPUB"]!)
        XCTAssertTrue(handled)
        XCTAssertEqual(viewModel.previewViewModel?.contentsState, .loading)

        await waitUntil {
            self.viewModel.previewViewModel?.contentsState == .loaded("Intro\n")
        }
        XCTAssertEqual(viewModel.previewViewModel?.contentsState, .loaded("Intro\n"))
    }

    func testMetadataRefresh() async throws {
        let book = mockCalibreBook!
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        let calibreServerService = mockAppContainer.calibreServerService
        let library = book.library
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: library.server, timeout: timeout, qos: qos)
                calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let bookEntryJson = """
            {
                "123": {
                    "authors": ["Refreshed Author"],
                    "formats": ["epub"],
                    "author_sort": "Author, Refreshed",
                    "title": "Refreshed Title",
                    "uuid": "uuid-apple",
                    "author_sort_map": {},
                    "identifiers": {},
                    "languages": ["eng"],
                    "pubdate": "",
                    "rating": 0.0,
                    "format_metadata": {},
                    "category_urls": {},
                    "tags": [],
                    "user_metadata": {},
                    "title_sort": "Apple",
                    "thumbnail": "/get/thumb/123/lib1",
                    "timestamp": "2023-07-21T07:43:05+00:00",
                    "user_categories": {},
                    "cover": "/get/cover/123/lib1",
                    "last_modified": "2023-07-25T03:11:04+00:00",
                    "application_id": 123
                }
            }
            """
            if request.url?.path.contains("book-get-annotations") == true {
                return (response, Data("{}".utf8))
            }
            return (response, bookEntryJson.data(using: .utf8)!)
        }
        
        viewModel.refresh(book: book)

        await waitUntil {
            self.viewModel.calibreBook?.title == "Refreshed Title"
        }

        mockAppContainer.refreshDatabase()
        
        guard let realm = mockAppContainer.databaseService.realm else {
            XCTFail("Realm is nil")
            return
        }
        
        await waitUntil { self.viewModel.refreshState == .synced }
        await calibreServerService.logger.flushPendingActivitiesForTesting()
        let activities = mockAppContainer.activityLogRepository.fetchTestSnapshots(libraryId: library.id, bookId: book.id, since: .distantPast)
        let batches = activities.filter { $0.kind == .batchMetadata }
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.bookIds, [book.id])
        XCTAssertEqual(batches.first?.state, .finished(.succeeded))
        XCTAssertEqual(batches.first?.result.requests.count, 1)
        XCTAssertEqual(activities.filter { $0.kind == .annotations }.count, 1)
        XCTAssertEqual(viewModel.refreshState, .synced)
        XCTAssertEqual(viewModel.calibreBook?.title, "Refreshed Title")
        XCTAssertEqual(
            realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: mockBookRealm.primaryKey!)?.title,
            "Refreshed Title"
        )
    }
}

@MainActor
private final class DetailRefreshController {
    private(set) var requests: [CalibreBooksMetadataRequest] = []
    private var continuations: [Int: CheckedContinuation<[Int32: BookMetadataRefreshResult], Never>] = [:]

    func refresh(_ request: CalibreBooksMetadataRequest) async -> [Int32: BookMetadataRefreshResult] {
        let index = requests.count
        requests.append(request)
        return await withCheckedContinuation { continuations[index] = $0 }
    }

    func complete(_ index: Int, with result: BookMetadataRefreshResult) {
        guard requests.indices.contains(index) else { XCTFail("Request did not start"); return }
        continuations.removeValue(forKey: index)?.resume(returning: [requests[index].books[0]: result])
    }
}

private final class DetailDownloadTask: URLSessionDownloadTask, @unchecked Sendable {
    private let url: URL
    override var originalRequest: URLRequest? { URLRequest(url: url) }
    override var response: URLResponse? {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    }
    init(url: URL) {
        self.url = url
        super.init()
    }
    override func cancel() {}
    override func cancel(byProducingResumeData completionHandler: @escaping (Data?) -> Void) {
        completionHandler(nil)
    }
}

private final class DetailHoldingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

@MainActor
class ReadingPositionViewModelTests: XCTestCase {
    var mockAppContainer: AppContainer!
    var listViewModel: ReadingPositionListViewModel!
    var mockBook: CalibreBook!
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ReadingPositionViewModelTests")

        let library = CalibreLibrary(server: CalibreServer(uuid: UUID(), name: "MockServer", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "lib1", name: "Mock Library")
        mockBook = CalibreBook(id: 123, library: library)
        mockBook.title = "Test Book"
        
        listViewModel = ReadingPositionListViewModel(container: mockAppContainer, book: mockBook, positions: [])
    }
    
    override func tearDownWithError() throws {
        listViewModel = nil
        mockBook = nil
        mockAppContainer = nil
    }
    
    func testDetailViewModelInitialization() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        let detailVM = ReadingPositionDetailViewModel(listModel: listViewModel, position: position)
        
        XCTAssertEqual(detailVM.position.id, "device-1")
        XCTAssertEqual(detailVM.selectedFormatReader, .YabrEPUB)
        XCTAssertEqual(detailVM.selectedFormat, .EPUB)
    }
    
    /// Marks the mock book's EPUB as cached and writes its file.
    private func makeCachedEPUB() throws {
        try makeCachedFormat(.EPUB)
    }

    /// Marks one of the mock book's formats as cached and writes its file.
    private func makeCachedFormat(_ format: Format) throws {
        mockBook.formats[format.rawValue] = FormatInfo(
            selected: true,
            filename: "position-test.\(format.ext)",
            serverSize: 1024,
            serverMTime: Date(),
            cached: true,
            cacheSize: 1024,
            cacheMTime: Date(),
            manifest: nil
        )
        listViewModel.book = mockBook

        let savedURL = try XCTUnwrap(getSavedUrl(book: mockBook, format: format))
        try FileManager.default.createDirectory(
            at: savedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: savedURL.path, contents: Data("EPUB".utf8)))
    }

    /// A history view model for the mock book, with these saved positions and sessions.
    private func makeHistoryViewModel(
        positions: [BookDeviceReadingPosition],
        sessions: [BookDeviceReadingPositionHistory] = [],
        now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }
    ) -> ReadingPositionHistoryViewModel {
        let bookRepository = MockBookRepository()
        bookRepository.getBookReturn = mockBook
        mockAppContainer.bookRepository = bookRepository

        let readingPositionRepository = MockReadingPositionRepository()
        readingPositionRepository.getPositionsReturn = positions
        mockAppContainer.readingPositionRepository = readingPositionRepository
        let history = MockReadingHistoryRepository()
        history.history = sessions
        mockAppContainer.readingHistoryRepository = history
        // The history list keeps only sessions of books on the shelf.
        mockAppContainer.booksInShelf[mockBook.inShelfId] = mockBook

        return ReadingPositionHistoryViewModel(
            container: mockAppContainer, book: mockBook,
            now: now, calendar: calendar
        )
    }

    func testListViewModelContinueReadingOpensReadingPositionPresentation() throws {
        try makeCachedEPUB()
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)

        let alert = listViewModel.continueReading(at: position, targetWorkspaceID: nil)

        XCTAssertNil(alert, "continueReading raised alert: \(alert?.id ?? "")")
        let presentation = mockAppContainer.sessionManager.activeReaderPresentation
        XCTAssertEqual(presentation?.book.inShelfId, mockBook.inShelfId)
        XCTAssertEqual(presentation?.source, .readingPosition)
        XCTAssertEqual(presentation?.readerInfo.position.id, "device-1")
        XCTAssertEqual(presentation?.readerInfo.readerType, .YabrEPUB)
    }

    /// Opening at a saved position is shared by every engine: each reopens with its own format,
    /// and YabrPDF resolves to Readium PDF where it isn't available.
    func testListViewModelContinueReadingOpensEveryEngineWithItsFormat() throws {
        let engines: [(ReaderType, Format)] = [
            (.YabrEPUB, .EPUB), (.ReadiumEPUB, .EPUB),
            (.YabrPDF, .PDF), (.ReadiumPDF, .PDF),
            (.ReadiumCBZ, .CBZ)
        ]
        for format in [Format.EPUB, .PDF, .CBZ] {
            try makeCachedFormat(format)
        }

        for (reader, format) in engines {
            let position = BookDeviceReadingPosition(id: "device-1", readerName: reader.rawValue)
            XCTAssertTrue(listViewModel.canContinueReading(at: position), "\(reader)")

            let alert = listViewModel.continueReading(at: position, targetWorkspaceID: nil)

            XCTAssertNil(alert, "\(reader) raised alert: \(alert?.id ?? "")")
            let presentation = try XCTUnwrap(mockAppContainer.sessionManager.activeReaderPresentation, "\(reader)")
            XCTAssertEqual(presentation.readerInfo.format, format, "\(reader)")
            XCTAssertEqual(presentation.readerInfo.readerType, reader.resolved(), "\(reader)")
            XCTAssertEqual(presentation.readerInfo.position.readerName, reader.rawValue, "\(reader)")
            mockAppContainer.sessionManager.closeReader(id: presentation.id)
        }
    }

    func testListViewModelContinueReadingAlertsWhenFormatNotCached() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)

        XCTAssertFalse(listViewModel.canContinueReading(at: position))
        let alert = listViewModel.continueReading(at: position, targetWorkspaceID: nil)

        XCTAssertEqual(alert?.id, "Selected Format Not Cached")
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testListViewModelContinueReadingAlertsForUnsupportedReader() throws {
        try makeCachedEPUB()
        let position = BookDeviceReadingPosition(id: "device-1", readerName: "NoSuchReader")

        XCTAssertFalse(listViewModel.canContinueReading(at: position))
        let alert = listViewModel.continueReading(at: position, targetWorkspaceID: nil)

        XCTAssertEqual(alert?.id, "Unsupported Reader")
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testDetailViewModelReadSelectedFormatHonorsReaderOverride() throws {
        try makeCachedEPUB()
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        let detailVM = ReadingPositionDetailViewModel(listModel: listViewModel, position: position)
        detailVM.selectedFormatReader = .ReadiumEPUB

        detailVM.readSelectedFormat(targetWorkspaceID: nil)

        XCTAssertNil(detailVM.alertItem, "readSelectedFormat raised alert: \(detailVM.alertItem?.id ?? "")")
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.readerInfo.readerType, .ReadiumEPUB)
    }

    func testHistoryViewModelBuildsDeviceSectionsNewestFirst() throws {
        try makeCachedEPUB()
        let now = Date().timeIntervalSince1970
        let historyVM = makeHistoryViewModel(positions: [
            TestFixtures.makeReadingPosition(id: "other-device", lastReadChapter: "Chapter 2", lastProgress: 20, epoch: now - 3600),
            TestFixtures.makeReadingPosition(id: mockAppContainer.deviceName, lastReadChapter: " Chapter 3\n", lastProgress: 30, epoch: now)
        ])

        historyVM.start()
        defer { historyVM.stop() }

        XCTAssertEqual(historyVM.bookIdentity, mockBook.inShelfId)
        XCTAssertEqual(historyVM.deviceSections.map(\.deviceName), [mockAppContainer.deviceName, "other-device"])
        XCTAssertEqual(historyVM.deviceSections.map(\.isThisDevice), [true, false])

        let latestRow = try XCTUnwrap(historyVM.deviceSections.first?.rows.first)
        XCTAssertEqual(latestRow.title, "Chapter 3")
        XCTAssertNil(latestRow.detail)
        XCTAssertFalse(latestRow.percentText.isEmpty)
        XCTAssertTrue(latestRow.canContinue)
    }

    func testHistoryViewModelBuildsLocalSessionRows() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-04-08T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = now.addingTimeInterval(-1800)
        let endPosition = TestFixtures.makeReadingPosition(
            id: mockAppContainer.deviceName,
            lastReadChapter: "Chapter 4",
            epoch: now.timeIntervalSince1970
        )
        let session = BookDeviceReadingPositionHistory(
            id: ReadingHistorySessionID(serverUUID: mockBook.library.server.uuid, objectID: "session"),
            bookId: mockBook.bookPrefId,
            startDatetime: start,
            startPosition: nil,
            endPosition: endPosition
        )
        let historyVM = makeHistoryViewModel(positions: [endPosition], sessions: [session],
                                             now: { now }, calendar: { calendar })

        historyVM.start()
        defer { historyVM.stop() }
        await expect(historyVM.$sessionRows) { $0.count == 1 }
        await expect(historyVM.statistics.$snapshot.map { $0?.minutesByDay ?? [] }) { $0.last == 30 }

        XCTAssertEqual(historyVM.sessionRows.count, 1)
        XCTAssertEqual(historyVM.sessionRows.first?.id, session.id)
        XCTAssertEqual(historyVM.sessionRows.first?.chapter, "Chapter 4")
        XCTAssertFalse(historyVM.sessionRows.first?.durationText.isEmpty ?? true)
        XCTAssertEqual(historyVM.statistics.minutes.count, ReadingStatisticsModel.previousDays + 1)
        XCTAssertEqual(historyVM.statistics.dayLabels.last, "Today")
        XCTAssertEqual(historyVM.statistics.todayMinutes, 30)
        XCTAssertEqual(historyVM.statistics.averageMinutes, 0)
        XCTAssertEqual(historyVM.statistics.maximumMinutes, 0)

        let repository = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        XCTAssertTrue(repository.detailIDs.isEmpty)
        let newer = BookDeviceReadingPositionHistory(
            id: ReadingHistorySessionID(serverUUID: mockBook.library.server.uuid, objectID: "newer-session"),
            bookId: mockBook.bookPrefId,
            startDatetime: now.addingTimeInterval(-900),
            startPosition: nil,
            endPosition: endPosition
        )
        repository.history.append(newer)
        repository.sessionChanges.send(())
        repository.statisticsChanges.send(())
        await expect(historyVM.$sessionRows) { $0.count == 2 }
        await expect(historyVM.statistics.$snapshot.map { $0?.minutesByDay ?? [] }) { $0.last == 45 }

        XCTAssertEqual(historyVM.sessionRows.map(\.id), [newer.id, session.id])
        XCTAssertEqual(historyVM.statistics.todayMinutes, 45)

        let selected = try XCTUnwrap(historyVM.sessionRows.last)
        historyVM.showDetail(for: selected)
        await expect(historyVM.$isDetailActive) { $0 }
        XCTAssertEqual(repository.detailIDs, [session.id])
        XCTAssertEqual(historyVM.displayedDetail?.position.epoch, endPosition.epoch)
    }

    func testHistoryViewModelContinueReadingRowOpensReader() throws {
        try makeCachedEPUB()
        let historyVM = makeHistoryViewModel(positions: [
            TestFixtures.makeReadingPosition(id: "device-1", lastReadChapter: "Chapter 5")
        ])
        historyVM.start()
        defer { historyVM.stop() }
        let row = try XCTUnwrap(historyVM.deviceSections.first?.rows.first)
        let workspaceID = UUID()

        historyVM.continueReading(row, targetWorkspaceID: workspaceID)

        XCTAssertNil(historyVM.alertItem, "continueReading raised alert: \(historyVM.alertItem?.id ?? "")")
        let presentation = mockAppContainer.sessionManager.activeReaderPresentation
        XCTAssertEqual(presentation?.source, .readingPosition)
        XCTAssertEqual(presentation?.readerInfo.position.lastReadChapter, "Chapter 5")
    }

    func testHistoryViewModelContinueReadingWithoutCachedFormatAlerts() throws {
        let historyVM = makeHistoryViewModel(positions: [
            TestFixtures.makeReadingPosition(id: "device-1")
        ])
        historyVM.start()
        defer { historyVM.stop() }
        let row = try XCTUnwrap(historyVM.deviceSections.first?.rows.first)
        XCTAssertFalse(row.canContinue)

        historyVM.continueReading(row, targetWorkspaceID: nil)

        XCTAssertEqual(historyVM.alertItem?.id, "Selected Format Not Cached")
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testHistoryViewModelDismissDetailKeepsDisplayedPositionForThePopAnimation() throws {
        let historyVM = makeHistoryViewModel(positions: [])
        let position = TestFixtures.makeReadingPosition(id: "device-1")

        historyVM.start()
        historyVM.showDetail(for: position)
        let detail = try XCTUnwrap(historyVM.displayedDetail)
        XCTAssertTrue(historyVM.isDetailActive)
        XCTAssertEqual(detail.position, position)

        historyVM.stop()
        historyVM.dismissDetail()
        historyVM.start()
        XCTAssertFalse(historyVM.isDetailActive)
        XCTAssertTrue(historyVM.displayedDetail === detail)
        historyVM.stop()
    }

    func testHistoryViewModelObservesPositionsOnlyWhileVisible() async throws {
        let historyVM = makeHistoryViewModel(positions: [])
        historyVM.start()
        XCTAssertTrue(historyVM.deviceSections.isEmpty)
        let list = try XCTUnwrap(historyVM.listViewModel)

        let positions = try XCTUnwrap(mockAppContainer.readingPositionRepository as? MockReadingPositionRepository)
        let history = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        await expect(historyVM.$sessionState.map { $0 == .loading }) { !$0 }
        let sectionLoads = history.sessionLimits.count
        positions.positionsBroadcaster.send([TestFixtures.makeReadingPosition(lastReadChapter: "Chapter 6")])
        await expect(historyVM.$deviceSections) { $0.first?.rows.first?.title == "Chapter 6" }
        XCTAssertEqual(history.sessionLimits.count, sectionLoads)
        XCTAssertTrue(historyVM.listViewModel === list)

        historyVM.stop()
        positions.positionsBroadcaster.send([])
        XCTAssertEqual(historyVM.deviceSections.first?.rows.first?.title, "Chapter 6")

        historyVM.start()
        XCTAssertTrue(historyVM.deviceSections.isEmpty)
        XCTAssertTrue(historyVM.listViewModel === list)
        historyVM.stop()
    }

    func testHistoryPagesKeepTheirLoadedRangeAndStatisticsUseAllSessions() async throws {
        let now = Date(timeIntervalSince1970: 1_712_577_600)
        let history = (0..<65).map { makeSession(index: $0, now: now) }
        let calendar = try utcCalendar()
        let view = makeHistoryViewModel(positions: [], sessions: history, now: { now }, calendar: { calendar })
        let repository = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        view.start()
        defer { view.stop() }
        await expect(view.$sessionRows) { $0.count == 30 }
        await expect(view.statistics.$snapshot.map { $0?.minutesByDay ?? [] }) { $0.last == 65 }
        XCTAssertTrue(view.hasMoreSessions)
        XCTAssertEqual(repository.sessionLimits, [30])

        view.loadMoreSessions()
        await expect(view.$sessionRows) { $0.count == 60 }
        XCTAssertEqual(repository.sessionLimits, [30, 60])
        XCTAssertEqual(view.statistics.todayMinutes, 65)

        view.stop()
        repository.history.removeLast(6)
        view.start()
        await expect(view.$sessionRows) { $0.count == 59 }
        XCTAssertEqual(repository.sessionLimits.last, 60)
        XCTAssertFalse(view.hasMoreSessions)
    }

    func testHistoryRejectsLatePageAfterDisappearanceAndKeepsRequestedLimit() async throws {
        let now = Date(timeIntervalSince1970: 1_712_577_600)
        let history = (0..<65).map { makeSession(index: $0, now: now) }
        let calendar = try utcCalendar()
        let view = makeHistoryViewModel(positions: [], sessions: history, now: { now }, calendar: { calendar })
        let repository = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        view.start()
        defer { view.stop() }
        await expect(view.$sessionRows) { $0.count == 30 }

        let suspended = expectation(description: "Load More suspended in repository")
        let returned = expectation(description: "Obsolete page returned")
        var release: CheckedContinuation<ReadingHistoryPage, Never>?
        repository.sessionRead = { _, _ in
            let page = await withCheckedContinuation { continuation in
                release = continuation
                suspended.fulfill()
            }
            returned.fulfill()
            return page
        }
        view.loadMoreSessions()
        view.loadMoreSessions()
        await fulfillment(of: [suspended], timeout: 5)
        view.stop()
        repository.sessionRead = nil
        repository.history.removeFirst()
        view.start()
        await expect(view.$sessionRows) { $0.first?.id == history[1].id && $0.count == 60 }

        let continuation = try XCTUnwrap(release)
        continuation.resume(returning: ReadingHistoryPage(rows: [], hasMore: false))
        await fulfillment(of: [returned], timeout: 5)
        XCTAssertEqual(view.sessionRows.first?.id, history[1].id)
        XCTAssertEqual(view.sessionRows.count, 60)
        XCTAssertEqual(repository.sessionLimits, [30, 60, 60])
    }

    func testHistoryUpdatesBookPresentationAndLegacyScopeIndependently() async throws {
        let now = Date(timeIntervalSince1970: 1_712_577_600)
        let legacy = makeSession(index: 0, now: now, legacy: true)
        let calendar = try utcCalendar()
        let view = makeHistoryViewModel(positions: [TestFixtures.makeReadingPosition()], sessions: [legacy],
                                        now: { now }, calendar: { calendar })
        let repository = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        view.start()
        defer { view.stop() }
        await expect(view.$sessionRows) { $0.count == 1 }
        await expect(view.statistics.$snapshot.map { $0?.minutesByDay ?? [] }) { $0.last == 1 }

        let unrelated = TestFixtures.makeBook(library: TestFixtures.makeLibrary(key: "unrelated"))
        mockAppContainer.booksInShelf[unrelated.inShelfId] = unrelated
        var changed = try XCTUnwrap(mockBook)
        changed.title = "Updated Title"
        changed.formats["EPUB"] = FormatInfo(selected: true, filename: "book.epub", serverSize: 1,
                                            serverMTime: now, cached: true, cacheSize: 1, cacheMTime: now)
        mockAppContainer.booksInShelf[changed.inShelfId] = changed
        await expect(view.$deviceSections) { $0.first?.rows.first?.canContinue == true }
        XCTAssertEqual(view.listViewModel?.book.title, "Updated Title")
        XCTAssertEqual(repository.sessionLimits.count, 1)
        XCTAssertEqual(repository.statisticsWindows.count, 1)

        let competitor = TestFixtures.makeLibrary(key: mockBook.library.key)
        mockAppContainer.calibreLibraries[competitor.id] = competitor
        await expect(view.$sessionRows) { $0.isEmpty }
        await expect(view.$sessionState.map { $0 == .loading }) { !$0 }
        XCTAssertEqual(view.statistics.todayMinutes, 0)
        mockAppContainer.calibreLibraries.removeValue(forKey: competitor.id)
        await expect(view.$sessionRows) { $0.count == 1 }

        let selected = try XCTUnwrap(view.sessionRows.first)
        repository.history = []
        view.showDetail(for: selected)
        await expect(view.$alertItem) { $0?.id == "Session Unavailable" }
        XCTAssertNil(view.displayedDetail)
    }

    func testHistoryClockChangesRequeryStatisticsWithoutReloadingThePage() async throws {
        let midnight = Date(timeIntervalSince1970: 1_712_620_800)
        var now = midnight.addingTimeInterval(-1)
        var calendar = try utcCalendar()
        let session = makeSession(index: 0, now: now)
        let view = makeHistoryViewModel(positions: [], sessions: [session], now: { now }, calendar: { calendar })
        let repository = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        view.start()
        defer { view.stop() }
        await expect(view.$sessionRows) { $0.count == 1 }
        await expect(view.statistics.$snapshot.map { $0?.minutesByDay ?? [] }) { $0.last == 1 }
        let before = try XCTUnwrap(repository.statisticsWindows.last)

        now = midnight
        view.clockDidChange()
        await expect(view.statistics.$snapshot.map { $0?.minutesByDay ?? [] }) { $0.suffix(2) == [1, 0] }
        XCTAssertNotEqual(repository.statisticsWindows.last?.sessionStartRange.lowerBound, before.sessionStartRange.lowerBound)
        XCTAssertEqual(repository.sessionLimits, [30])

        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        view.clockDidChange()
        await expect(view.statistics.$snapshot.map { $0?.minutesByDay ?? [] }) { $0.last == 1 }
        XCTAssertEqual(repository.statisticsWindows.last?.calendar.timeZone.identifier, "America/Los_Angeles")
        XCTAssertEqual(repository.sessionLimits, [30])
    }

    func testSessionFailureRetriesAndLateDetailCannotReplaceSelectedPosition() async throws {
        let now = Date(timeIntervalSince1970: 1_712_577_600)
        let session = makeSession(index: 0, now: now)
        let view = makeHistoryViewModel(positions: [], sessions: [session], now: { now })
        let repository = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        repository.sessionRead = { _, _ in throw URLError(.cannotConnectToHost) }
        XCTAssertEqual(view.sessionState, .loading)
        view.start()
        defer { view.stop() }
        await expect(view.$sessionState) { $0 == .failed }
        repository.sessionRead = nil
        view.retrySessions()
        await expect(view.$sessionRows) { $0.count == 1 }
        XCTAssertEqual(view.sessionState, .ready)

        let entered = expectation(description: "Selected session detail suspended")
        let returned = expectation(description: "Old detail returned")
        var release: CheckedContinuation<BookDeviceReadingPosition?, Never>?
        repository.positionRead = { _, _ in
            let position = await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
            returned.fulfill()
            return position
        }
        view.showDetail(for: try XCTUnwrap(view.sessionRows.first))
        await fulfillment(of: [entered], timeout: 5)
        let chosen = TestFixtures.makeReadingPosition(lastReadChapter: "Chosen Position", epoch: now.timeIntervalSince1970)
        view.showDetail(for: chosen)
        let displayed = try XCTUnwrap(view.displayedDetail)
        let continuation = try XCTUnwrap(release)
        continuation.resume(returning: session.endPosition)
        await fulfillment(of: [returned], timeout: 5)
        XCTAssertTrue(view.displayedDetail === displayed)
        XCTAssertEqual(view.displayedDetail?.position.lastReadChapter, "Chosen Position")
        view.dismissDetail()
        XCTAssertTrue(view.displayedDetail === displayed)
    }

    func testSessionDetailCannotPushAfterTheBookLeavesTheShelf() async throws {
        let now = Date(timeIntervalSince1970: 1_712_577_600)
        let session = makeSession(index: 0, now: now)
        let view = makeHistoryViewModel(positions: [], sessions: [session], now: { now })
        let repository = try XCTUnwrap(mockAppContainer.readingHistoryRepository as? MockReadingHistoryRepository)
        view.start()
        defer { view.stop() }
        await expect(view.$sessionRows) { $0.count == 1 }
        let entered = expectation(description: "Session detail suspended")
        let returned = expectation(description: "Unavailable detail returned")
        var release: CheckedContinuation<BookDeviceReadingPosition?, Never>?
        repository.positionRead = { _, _ in
            let value = await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
            returned.fulfill()
            return value
        }
        view.showDetail(for: try XCTUnwrap(view.sessionRows.first))
        await fulfillment(of: [entered], timeout: 5)
        mockAppContainer.booksInShelf.removeValue(forKey: mockBook.inShelfId)
        await expect(view.$sessionRows) { $0.isEmpty }
        let continuation = try XCTUnwrap(release)
        continuation.resume(returning: session.endPosition)
        await fulfillment(of: [returned], timeout: 5)
        XCTAssertFalse(view.isDetailActive)
        XCTAssertNil(view.displayedDetail)
    }

    func testDetailObservesCacheWhileKeepingItsChosenPosition() async throws {
        try makeCachedEPUB()
        let books = MockBookRepository()
        books.getBookReturn = mockBook
        mockAppContainer.bookRepository = books
        let list = ReadingPositionListViewModel(container: mockAppContainer, book: mockBook, positions: [])
        let position = TestFixtures.makeReadingPosition(lastReadChapter: "Chosen")
        let detail = ReadingPositionDetailViewModel(listModel: list, position: position)
        let initial = expectation(description: "Initial detail metadata")
        let initialObservation = detail.objectWillChange.first().sink { initial.fulfill() }
        detail.start()
        detail.start()
        defer { detail.stop() }
        await fulfillment(of: [initial], timeout: 5)
        initialObservation.cancel()
        XCTAssertTrue(detail.isSelectedFormatCached)
        var changed = try XCTUnwrap(mockBook)
        changed.formats["EPUB"]?.cached = false
        books.getBookReturn = changed
        let updated = expectation(description: "Detail book metadata updated")
        let observation = detail.objectWillChange.first().sink { updated.fulfill() }
        books.sendObservedBook(changed)
        await fulfillment(of: [updated], timeout: 5)
        observation.cancel()
        XCTAssertFalse(detail.isSelectedFormatCached)
        XCTAssertEqual(detail.position.lastReadChapter, "Chosen")
        detail.readSelectedFormat(targetWorkspaceID: nil)
        XCTAssertEqual(detail.alertItem?.id, "Selected Format Not Cached")
    }

    private func makeSession(index: Int, now: Date, legacy: Bool = false) -> BookDeviceReadingPositionHistory {
        let end = now.addingTimeInterval(-Double(index) * 60)
        return BookDeviceReadingPositionHistory(
            id: .init(serverUUID: legacy ? nil : mockBook.library.server.uuid, objectID: "session-\(index)"),
            bookId: mockBook.bookPrefId, startDatetime: end.addingTimeInterval(-60), startPosition: nil,
            endPosition: TestFixtures.makeReadingPosition(epoch: end.timeIntervalSince1970)
        )
    }

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return calendar
    }

    private func expect<P: Publisher>(_ publisher: P, where predicate: @escaping (P.Output) -> Bool) async
    where P.Failure == Never {
        let published = expectation(description: "Expected history snapshot")
        let subscription = publisher.first(where: predicate).sink { _ in published.fulfill() }
        await fulfillment(of: [published], timeout: 5)
        subscription.cancel()
    }

    func testDetailViewModelReadSelectedFormatOpensReaderPresentation() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        try makeCachedEPUB()
        let detailVM = ReadingPositionDetailViewModel(listModel: listViewModel, position: position)

        detailVM.readSelectedFormat(targetWorkspaceID: nil)

        XCTAssertNil(detailVM.alertItem, "readSelectedFormat raised alert: \(detailVM.alertItem?.id ?? "")")
        let presentation = mockAppContainer.sessionManager.activeReaderPresentation
        XCTAssertEqual(presentation?.book.inShelfId, mockBook.inShelfId)
        XCTAssertEqual(presentation?.source, .readingPosition)
        XCTAssertEqual(presentation?.readerInfo.position.id, position.id)
    }
    
    func testHistoryViewModelLoadData() throws {
        let historyVM = ReadingPositionHistoryViewModel(container: mockAppContainer, book: mockBook)
        XCTAssertEqual(historyVM.statistics.maximumMinutes, 0)
        
        historyVM.start()
        defer { historyVM.stop() }
        
        XCTAssertEqual(historyVM.statistics.state, .loading)
        XCTAssertNil(historyVM.statistics.snapshot)
    }

    func testHistoryViewModelUsesBookRepositoryAndReadingPositionRepositoryForHistory() throws {
        let bookRepository = MockBookRepository()
        bookRepository.getBookReturn = mockBook
        mockAppContainer.bookRepository = bookRepository

        let readingPositionRepository = MockReadingPositionRepository()
        readingPositionRepository.debugPositionsReturn = [
            BookDeviceReadingPosition(id: "debug-device", readerName: ReaderType.YabrEPUB.rawValue)
        ]
        mockAppContainer.readingPositionRepository = readingPositionRepository

        let historyVM = ReadingPositionHistoryViewModel(container: mockAppContainer, book: mockBook)
        historyVM.start()
        defer { historyVM.stop() }

        XCTAssertTrue(bookRepository.getBookCalled)
        XCTAssertEqual(bookRepository.getBookBookIdParam, mockBook.id)
        XCTAssertEqual(bookRepository.getBookLibraryParam, mockBook.library)
        XCTAssertTrue(readingPositionRepository.debugPositionsCalled)
        XCTAssertEqual(historyVM.listViewModel?.book.id, mockBook.id)
        XCTAssertEqual(historyVM.debugReadingPositions.first?.id, "debug-device")
    }
}

@MainActor
class ActivityListViewModelTests: XCTestCase {
    func testObservationFollowsVisibilityAndRetainsTheLoadedWindow() async throws {
        let repository = MockActivityLogRepository()
        let initial = summary()
        repository.page = .init(entries: [initial], hasMore: true)
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        let model = ActivityListViewModel(repository: repository, libraryId: "library-id", bookId: 7,
                                          pageSize: 2, now: { date })
        XCTAssertTrue(repository.pageFetches.isEmpty)
        model.start()
        model.start()
        XCTAssertEqual(repository.pageObservations.count, 1)
        XCTAssertEqual(model.page.entries, [initial])
        XCTAssertEqual(repository.pageFetches.last?.query.libraryId, "library-id")
        XCTAssertEqual(repository.pageFetches.last?.query.bookId, 7)
        XCTAssertEqual(repository.pageFetches.last?.query.since, ActivityLogRetention.cutoff(at: date))

        model.loadMore()
        XCTAssertEqual(repository.pageObservations.last?.limit, 4)
        let newer = summary()
        let changed = ActivityLogPage(entries: [newer, initial])
        repository.pageObservations[1].stream.send(changed)
        try await waitUntil { model.page == changed }
        model.stop()
        model.stop()
        repository.pageObservations[1].stream.send(.init())
        try await waitUntil { repository.pageSubscriberCount == 0 }
        XCTAssertEqual(model.page, changed)

        date = date.addingTimeInterval(60)
        repository.page = changed
        model.start()
        XCTAssertEqual(repository.pageFetches.last?.limit, 4)
        XCTAssertEqual(repository.pageFetches.last?.query.since, ActivityLogRetention.cutoff(at: date))
        date = date.addingTimeInterval(60)
        model.refreshIfVisible()
        XCTAssertEqual(repository.pageFetches.last?.limit, 4)
        XCTAssertEqual(repository.pageFetches.last?.query.since, ActivityLogRetention.cutoff(at: date))
        model.stop()
    }

    func testChangingFiltersResetsPagingAndRejectsLateResults() async throws {
        let repository = MockActivityLogRepository()
        let original = summary()
        repository.page = .init(entries: [original], hasMore: true)
        let model = ActivityListViewModel(repository: repository, libraryId: "A", bookId: 7, pageSize: 2)
        model.start()
        model.loadMore()
        XCTAssertEqual(repository.pageFetches.last?.limit, 4)

        repository.page = .init()
        model.filter = .init(kind: .download, failuresOnly: true)
        XCTAssertEqual(repository.pageFetches.last?.limit, 2)
        XCTAssertEqual(repository.pageFetches.last?.query.filter, model.filter)
        XCTAssertEqual(repository.pageFetches.last?.query.libraryId, "A")
        XCTAssertEqual(repository.pageFetches.last?.query.bookId, 7)
        model.loadMore()
        XCTAssertEqual(repository.pageObservations.count, 3)

        let failure = summary(kind: .download, state: .finished(.failed))
        let expected = ActivityLogPage(entries: [failure])
        repository.pageObservations[2].stream.send(expected)
        repository.pageObservations[1].stream.send(.init(entries: [original], hasMore: true))
        try await waitUntil { model.page == expected && repository.pageSubscriberCount == 1 }
        XCTAssertEqual(model.page.entries, [failure])

        model.filter = .init()
        XCTAssertEqual(repository.pageObservations.last?.query.filter, .init())
        XCTAssertEqual(repository.pageObservations.last?.limit, 2)
        model.stop()
    }

    func testDetailObservesItsIDAfterListStopsAndClearsDeletedRecord() async throws {
        let repository = MockActivityLogRepository()
        let first = snapshot(state: .inProgress(.running))
        let other = snapshot(state: .finished(.succeeded))
        repository.details = [first.id: first, other.id: other]
        let list = ActivityListViewModel(repository: repository, libraryId: "A", bookId: 7)
        list.start()
        let detail = list.makeDetailViewModel(id: first.id)
        list.stop()
        detail.start()
        detail.start()
        XCTAssertEqual(detail.entry, first)
        XCTAssertEqual(repository.detailObservations.count, 1)
        XCTAssertEqual(repository.detailObservations[0].id, first.id)
        XCTAssertEqual(repository.detailObservations[0].bookId, 7)

        let completed = snapshot(id: first.id, state: .finished(.failed))
        repository.detailObservations[0].stream.send(completed)
        try await waitUntil { detail.entry == completed && repository.pageSubscriberCount == 0 }
        repository.details.removeValue(forKey: first.id)
        repository.detailObservations[0].stream.send(nil)
        try await waitUntil { detail.entry == nil }

        detail.stop()
        detail.stop()
        let next = list.makeDetailViewModel(id: other.id)
        next.start()
        repository.detailObservations[0].stream.send(completed)
        try await waitUntil { repository.detailSubscriberCount == 1 }
        XCTAssertNil(detail.entry)
        XCTAssertEqual(next.entry, other)
        next.stop()
    }

    func testDetailRechecksRetentionAndCancelsWhenReleased() async throws {
        let repository = MockActivityLogRepository()
        let activity = snapshot(state: .inProgress(.paused))
        repository.details[activity.id] = activity
        var date = activity.startDatetime
        var detail: ActivityDetailViewModel? = ActivityDetailViewModel(
            id: activity.id, repository: repository, now: { date }
        )
        weak var retained = detail
        detail?.start()
        XCTAssertEqual(detail?.entry, activity)
        date = date.addingTimeInterval(8 * 24 * 60 * 60)
        detail?.refreshIfVisible()
        XCTAssertNil(detail?.entry)
        XCTAssertEqual(repository.detailObservations.last?.since, ActivityLogRetention.cutoff(at: date))
        detail = nil
        XCTAssertNil(retained)
        try await waitUntil { repository.detailSubscriberCount == 0 }
    }

    private func summary(kind: ActivityLogKind = .bookMetadata, state: ActivityLogState = .inProgress(.running)) -> ActivityLogSummary {
        .init(id: ActivityID(), kind: kind, state: state, startDatetime: Date(),
              finishDatetime: nil, libraryName: "Library", bookTitle: "Book",
              legacyType: nil, downloadFormat: nil, resultPreview: nil)
    }

    private func snapshot(id: ActivityID = ActivityID(), state: ActivityLogState) -> ActivityLogSnapshot {
        .init(id: id, kind: .download, state: state, startDatetime: Date(), finishDatetime: nil,
              result: .init(), request: .init(endpointURL: "http://localhost", httpMethod: "GET", httpBody: nil, headers: []),
              libraryId: "A", bookIds: [7], libraryName: "Library", bookTitle: "Book",
              legacyType: nil, legacyResult: nil, downloadFormat: "EPUB")
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(predicate(), file: file, line: line)
    }
}

@MainActor
class LibraryViewModelTests: XCTestCase {
    func testInitializationReadsPersistedFlagsAndObservesUpdates() async throws {
        let container = MockAppContainerFactory.makeContainer(testName: "LibraryViewModelTests")
        var library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        library.discoverable = false
        let repository = MockLibraryRepository()
        repository.getLibraryReturn = library

        let viewModel = LibraryViewModel(container: container, library: library, libraryRepository: repository)
        XCTAssertFalse(viewModel.discoverable)

        for _ in 0..<50 where repository.observeLibrarySubscriberCount == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(repository.getLibraryCalled)
        XCTAssertTrue(repository.observeLibraryCalled)
        XCTAssertEqual(repository.observeLibrarySubscriberCount, 1)

        var updatedLibrary = library
        updatedLibrary.discoverable = true
        repository.sendObservedLibrary(updatedLibrary)
        for _ in 0..<50 where !viewModel.discoverable {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(viewModel.discoverable)
    }

    func testFlagMutationsCallUpdateLibraryFlags() throws {
        let container = MockAppContainerFactory.makeContainer(testName: "LibraryViewModelTests")
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let repository = MockLibraryRepository()
        repository.getLibraryReturn = library

        let manager = CalibreLibraryManager(container: container, databaseService: container.databaseService,
                                            libraryRepository: repository)
        manager.calibreLibraries[library.id] = library
        container.libraryManager = manager
        let viewModel = LibraryViewModel(container: container, library: library, libraryRepository: repository)
        repository.updateLibraryFlagsCalled = false
        repository.updateLibraryFlagsError = CocoaError(.fileWriteNoPermission)

        viewModel.setDiscoverable(!library.discoverable)
        XCTAssertTrue(repository.updateLibraryFlagsCalled)
        XCTAssertEqual(viewModel.discoverable, library.discoverable)
        XCTAssertEqual(container.libraryManager.calibreLibraries[library.id]?.discoverable, library.discoverable)
        XCTAssertEqual(viewModel.saveFailure, .failed)

        repository.updateLibraryFlagsError = nil
        viewModel.setDiscoverable(!library.discoverable)

        XCTAssertTrue(repository.updateLibraryFlagsCalled)
        XCTAssertEqual(repository.updateLibraryFlagsIdParam, library.id)
        XCTAssertEqual(repository.updateLibraryFlagsDiscoverableParam, !library.discoverable)
        // The manager's copy too, which it saves whole.
        XCTAssertEqual(container.libraryManager.calibreLibraries[library.id]?.discoverable, !library.discoverable)
        XCTAssertNil(viewModel.saveFailure)
    }
}

class ReadingPositionRepositoryThreadingTests: XCTestCase {
    var mockAppContainer: AppContainer!
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ReadingPositionRepositoryThreadingTests")
        try! mockAppContainer.databaseService.realm!.write {
            mockAppContainer.databaseService.realm!.deleteAll()
        }
    }
    
    override func tearDownWithError() throws {
        mockAppContainer = nil
    }
    
    func testGetPositionsCanReadFromBackgroundQueue() throws {
        let library = mockAppContainer.calibreLibraries.first?.value ?? CalibreLibrary(
            server: CalibreServer(uuid: UUID(), name: "MockServer", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""),
            key: "lib1",
            name: "Mock Library"
        )
        
        mockAppContainer.calibreLibraries[library.id] = library
        
        var book = CalibreBook(id: 456, library: library)
        book.title = "Threading Test Book"
        
        let position = BookDeviceReadingPosition(
            id: "thread-test-device",
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 7,
            lastProgress: 42.0,
            epoch: Date().timeIntervalSince1970
        )
        mockAppContainer.readingPositionRepository.savePosition(position, for: book)
        
        let expectation = expectation(description: "Background queue can read reading positions")
        let queue = DispatchQueue(label: "reading-position-thread-test")
        
        queue.async {
            let positions = self.mockAppContainer.readingPositionRepository.getPositions(for: book)
            XCTAssertTrue(positions.contains(where: { $0.id == "thread-test-device" }))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }


}

private final class PausingMetadataBookRepository: RealmBookRepository {
    var blockAfterCommit = false
    var atBoundary: () -> Void = {}
    var failCommit = false

    override func commitMetadataWrite(in realm: Realm) throws {
        if failCommit { throw BookMetadataStorageError.writeFailed }
        try super.commitMetadataWrite(in: realm)
    }

    override func persistMetadataEntries(scope: BookMetadataRefreshScope, bookIDs: [Int32],
                                        answers: [Int32: BookMetadataAnswer]) throws -> [Int32: BookMetadataPersistenceResult] {
        if !blockAfterCommit { atBoundary() }
        let result = try super.persistMetadataEntries(scope: scope, bookIDs: bookIDs, answers: answers)
        if blockAfterCommit { atBoundary() }
        return result
    }
}

@MainActor
final class BookMetadataPublicationDateTests: XCTestCase {
    private func makeBook() -> CalibreBook {
        let server = CalibreServer(uuid: UUID(), name: "Metadata", baseUrl: "http://localhost",
            hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        return CalibreBook(id: 1, library: CalibreLibrary(server: server, key: "metadata", name: "Metadata"))
    }

    func testPublicationDateKeepsValidDatesWithPreferredCalendar() throws {
        if let expected = ProcessInfo.processInfo.environment["YABR_TEST_EXPECTED_CALENDAR"] {
            XCTAssertEqual(String(describing: Calendar.current.identifier), expected)
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var book = makeBook()
        for year in [2024, 2000] {
            book.pubDate = try XCTUnwrap(gregorian.date(from: DateComponents(year: year, month: 6, day: 1, hour: 12)))
            let section = BookMetadataSection(book: book, goodreadsRating: nil, goodreadsShelves: nil)
            XCTAssertEqual(section.publicationDate, book.pubDateByLocale, "Valid Gregorian year \(year) must remain visible")
        }
    }

    func testPublicationDateOmitsCalibreSentinelWithPreferredCalendar() throws {
        if let expected = ProcessInfo.processInfo.environment["YABR_TEST_EXPECTED_CALENDAR"] {
            XCTAssertEqual(String(describing: Calendar.current.identifier), expected)
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let sentinel = try XCTUnwrap(gregorian.date(from: DateComponents(year: 101, month: 1, day: 1, hour: 12)))
        var book = makeBook()
        for date in [Date(timeIntervalSince1970: 0), Date.distantPast, sentinel] {
            book.pubDate = date
            XCTAssertNil(BookMetadataSection(book: book, goodreadsRating: nil, goodreadsShelves: nil).publicationDate)
        }
    }

}

@MainActor
final class BookPreviewLifecycleTests: XCTestCase {
    private func preview(book: CalibreBook = TestFixtures.makeBook(), format: Format = .EPUB,
                         manifest: @escaping () async throws -> Data,
                         local: @escaping () async throws -> String = { throw URLError(.cannotDecodeContentData) }) -> BookPreviewViewModel {
        let reader = ReaderType.readers(for: format).first ?? .UNSUPPORTED
        return BookPreviewViewModel(book: book,
            readerInfo: ReaderInfo(deviceName: "preview-test", url: URL(fileURLWithPath: "/preview.\(format.ext)"),
                missing: false, format: format, readerType: reader,
                position: TestFixtures.makeReadingPosition(readerName: reader.rawValue)),
            loadManifest: manifest, loadLocalContents: local)
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Preview did not reach the expected state")
    }

    func testClosedPreviewRejectsLateResponse() async {
        let response = DeferredPreviewManifest()
        let model = preview(manifest: { try await response.load() })
        model.start()
        await waitFor { response.requests.count == 1 }
        model.cancel()
        response.requests[0].resume(returning: Data("{\"toc\":{\"children\":[{\"title\":\"Late\"}]}}".utf8))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.contentsState, .loading)
    }

    func testRetryRejectsOldResponseAndAcceptsNewOne() async {
        let response = DeferredPreviewManifest()
        let model = preview(manifest: { try await response.load() })
        model.start()
        model.start()
        await waitFor { response.requests.count == 1 }
        model.loadContents()
        await waitFor { response.requests.count == 2 }
        response.requests[1].resume(returning: Data("{\"toc\":{\"children\":[{\"title\":\"New\"}]}}".utf8))
        await waitFor { model.contentsState == .loaded("New\n") }
        response.requests[0].resume(returning: Data("{\"toc\":{\"children\":[{\"title\":\"Old\"}]}}".utf8))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.contentsState, .loaded("New\n"))
    }

    func testLatePreviewACannotOverwritePreviewBWithSameNumericBookID() async {
        let response = DeferredPreviewManifest()
        let first = preview(manifest: { try await response.load() })
        let second = preview(format: .PDF, manifest: { Data("{\"toc\":{\"children\":[{\"title\":\"B\"}]}}".utf8) })
        XCTAssertEqual(first.book.id, second.book.id)
        XCTAssertNotEqual(first.book.inShelfId, second.book.inShelfId)
        first.start()
        await waitFor { response.requests.count == 1 }
        first.cancel()
        second.start()
        await waitFor { second.contentsState == .loaded("B\n") }
        response.requests[0].resume(returning: Data("{\"toc\":{\"children\":[{\"title\":\"A\"}]}}".utf8))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(second.contentsState, .loaded("B\n"))
        XCTAssertEqual(second.readerInfo.format, .PDF)
    }

    func testNetworkFailureIsRecoverable() async {
        var attempts = 0
        let model = preview(manifest: {
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return Data("{\"toc\":{\"children\":[{\"title\":\"Recovered\"}]}}".utf8)
        })
        model.start()
        await waitFor { if case .failed = model.contentsState { return true }; return false }
        model.loadContents()
        await waitFor { model.contentsState == .loaded("Recovered\n") }
        XCTAssertEqual(attempts, 2)
    }

    func testOfflinePreviewUsesDownloadedContents() async {
        let model = preview(manifest: { throw URLError(.notConnectedToInternet) }, local: { "Local chapter\n" })
        model.start()
        await waitFor { model.contentsState == .loaded("Local chapter\n") }
    }

    func testLocalPreviewNeverRequestsServer() async {
        let localBook = TestFixtures.makeBook(library: TestFixtures.makeLibrary(server: TestFixtures.makeServer(baseUrl: ".")))
        let model = preview(book: localBook, manifest: { XCTFail("Local file must not use Calibre"); return Data() }, local: { "Local\n" })
        model.start()
        await waitFor { model.contentsState == .loaded("Local\n") }
    }

    func testCachedManifestCanBeUsedOffline() async {
        var book = TestFixtures.makeBook()
        book.formats["EPUB"] = FormatInfo(serverSize: 0, serverMTime: .distantPast,
            cached: true, cacheSize: 0, cacheMTime: .distantPast,
            manifest: Data("{\"toc\":{\"children\":[{\"title\":\"Saved\"}]}}".utf8))
        let model = preview(book: book, manifest: { XCTFail("Saved contents should be used"); return Data() })
        model.start()
        await waitFor { model.contentsState == .loaded("Saved\n") }
    }

    func testLocalParserReadsTheBundledEPUBWithoutAReadingSession() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "UI Test Fixture", withExtension: "epub"))
        let contents = try await BookPreviewViewModel.localContents(url: url)
        XCTAssertTrue(contents.contains("The Compass and the Quiet Map"), contents)
    }

    func testLocalParserPreservesPDFAndCBZWithoutContents() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdfURL = folder.appendingPathComponent("preview.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300))
        try renderer.pdfData { context in
            context.beginPage()
            "PDF Preview".draw(at: CGPoint(x: 20, y: 20))
        }.write(to: pdfURL)
        let imageURL = folder.appendingPathComponent("page.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
        try XCTUnwrap(image.pngData()).write(to: imageURL)
        let cbzURL = folder.appendingPathComponent("preview.cbz")
        try Zip.zipFiles(paths: [imageURL], zipFilePath: cbzURL, password: nil, progress: nil)
        let pdfContents = try await BookPreviewViewModel.localContents(url: pdfURL)
        let cbzContents = try await BookPreviewViewModel.localContents(url: cbzURL)
        XCTAssertEqual(pdfContents, "")
        XCTAssertEqual(cbzContents, "")
    }

    func testGeneratingManifestCanBeRetriedToAnEmptyContentsResult() async {
        var requests = 0
        let model = preview(manifest: {
            requests += 1
            return Data((requests == 1 ? "{\"job_status\":\"waiting\"}" : "{\"toc\":{\"children\":[]}}").utf8)
        })
        model.start()
        await waitFor { model.contentsState == .generating }
        model.loadContents()
        await waitFor { model.contentsState == .empty }
    }

    func testEmptyGeneratingNestedAndMalformedManifests() {
        for json in ["{}", "{\"toc\":null}", "{\"toc\":{\"children\":[]}}"] {
            XCTAssertEqual(BookPreviewViewModel.parseManifest(Data(json.utf8)), .empty)
        }
        for status in ["waiting", "running", "working"] {
            XCTAssertEqual(BookPreviewViewModel.parseManifest(Data("{\"job_status\":\"\(status)\"}".utf8)), .generating)
        }
        let nested = Data("{\"toc\":{\"children\":[{\"title\":\"One\",\"children\":[{\"title\":\"Two\"}]}]}}".utf8)
        XCTAssertEqual(BookPreviewViewModel.parseManifest(nested), .loaded("One\n  Two\n"))
        for json in ["[]", "invalid", "{\"toc\":[]}", "{\"toc\":{\"children\":\"invalid\"}}", "{\"job_status\":\"failed\"}", "{\"aborted\":true}", "{\"traceback\":\"server error\"}", "{\"toc\":{\"children\":[{\"title\":123}]}}"] {
            guard case .failed = BookPreviewViewModel.parseManifest(Data(json.utf8)) else {
                return XCTFail("Malformed manifest must allow retry: \(json)")
            }
        }
    }
}

@MainActor
private final class DeferredPreviewManifest {
    var requests: [CheckedContinuation<Data, Error>] = []
    func load() async throws -> Data {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
}

@MainActor
final class BookDescriptionWebViewTests: XCTestCase {
    func testOnlyDocumentChangesReloadWebKitWhileLayoutChangesReflow() async throws {
        let base = try XCTUnwrap(URL(string: "https://example.invalid/first/book"))
        let html = "<p>\(String(repeating: "An ordinary description wraps at the container width. ", count: 18))</p>"
            + "<a href='details'>Details</a>"
        var measuredDocument: BookDescriptionDocument?
        var height: CGFloat = 0
        let coordinator = BookDescriptionWebView.Coordinator()
        let webView = coordinator.makeWebView()
        webView.frame = CGRect(x: 0, y: 0, width: 300, height: 140)
        let root = UIViewController()
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.rootViewController = root
        root.view.addSubview(webView)
        window.isHidden = false
        defer {
            BookDescriptionWebView.dismantleUIView(webView, coordinator: coordinator)
            window.isHidden = true
            window.rootViewController = nil
        }
        func update(_ document: BookDescriptionDocument, size: CGFloat = 17) {
            coordinator.update(BookDescriptionWebView(document: document, textSize: size,
                openLink: { _ in }, onHeight: {
                    measuredDocument = $0
                    height = $1
                }, revealAnchor: { _ in }), in: webView)
        }

        let initial = BookDescriptionDocument(html: html, baseURL: base)
        update(initial)
        try await waitFor { height > 140 }
        let wideHeight = height
        XCTAssertFalse(webView.scrollView.isScrollEnabled)
        let token = try await documentToken(in: webView)
        let originalLink = try await webView.evaluateJavaScript("document.querySelector('a').href") as? String
        XCTAssertEqual(originalLink, "https://example.invalid/first/details")

        update(initial) // Same inputs as a download-progress update.
        webView.frame.size.width = 180
        try await waitFor { height > wideHeight }
        let narrowHeight = height
        update(initial, size: 25)
        try await waitFor { height > narrowHeight }
        let reflowedToken = try await documentToken(in: webView)
        XCTAssertEqual(reflowedToken, token)
        XCTAssertEqual(webView.bounds.height, 140)

        let otherBase = try XCTUnwrap(URL(string: "https://example.invalid/second/book"))
        let moved = BookDescriptionDocument(html: html, baseURL: otherBase)
        update(moved, size: 25)
        try await waitFor { measuredDocument == moved }
        let newBaseToken = try await documentToken(in: webView)
        XCTAssertNotEqual(newBaseToken, token)
        let updatedLink = try await webView.evaluateJavaScript("document.querySelector('a').href") as? String
        XCTAssertEqual(updatedLink, "https://example.invalid/second/details")

        let updated = BookDescriptionDocument(html: "<p>Updated description</p>", baseURL: otherBase)
        update(updated, size: 25)
        try await waitFor { measuredDocument == updated && (1..<140).contains(height) }
        let newContentToken = try await documentToken(in: webView)
        XCTAssertNotEqual(newContentToken, newBaseToken)
        let updatedBody = try await webView.evaluateJavaScript("document.body.innerText.trim()") as? String
        XCTAssertEqual(updatedBody, "Updated description")

        let disclosure = BookDescriptionDocument(html: """
            <details><summary>Synopsis</summary><p>\(String(repeating: "The synopsis continues. ", count: 20))</p></details>
            """, baseURL: otherBase)
        update(disclosure)
        try await waitFor { measuredDocument == disclosure && !webView.isLoading }
        let summaryHeight = height
        XCTAssertTrue((1..<140).contains(summaryHeight))
        let disclosureToken = try await documentToken(in: webView)
        let toggleDisclosure = "document.querySelector('summary').click(); document.querySelector('details').open"

        let isOpen = try await webView.evaluateJavaScript(toggleDisclosure) as? Bool
        XCTAssertEqual(isOpen, true)
        try await waitFor { height > 180 }
        let isStillOpen = try await webView.evaluateJavaScript(toggleDisclosure) as? Bool
        XCTAssertEqual(isStillOpen, false)
        try await waitFor { height == summaryHeight }
        let remeasuredToken = try await documentToken(in: webView)
        XCTAssertEqual(remeasuredToken, disclosureToken)

        let empty = BookDescriptionDocument(html: "<p><br>&nbsp;</p>", baseURL: nil)
        update(empty)
        try await waitFor { measuredDocument == empty }
        XCTAssertEqual(height, 0)
    }

    private func documentToken(in webView: WKWebView) async throws -> String {
        let token = try await webView.evaluateJavaScript("document.querySelector('meta[name=yabr-description]').content")
        return try XCTUnwrap(token as? String)
    }

    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "WebKit did not report the expected layout", file: file, line: line)
    }

}
