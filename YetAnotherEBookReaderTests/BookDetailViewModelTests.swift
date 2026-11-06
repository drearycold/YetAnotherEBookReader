import XCTest
import SwiftUI
import Combine
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
        mockAppContainer.serverManager.addServer(server: server, libraries: [library])

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
        XCTAssertNil(viewModel.listVM)
    }

    func testDeletedBookClearsObservedDetail() async throws {
        mockAppContainer.bookRepository.deleteBook(id: mockCalibreBook.inShelfId)
        await waitUntil { self.viewModel.calibreBook == nil }
        XCTAssertNil(viewModel.calibreBook)
        XCTAssertNil(viewModel.listVM)
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
        XCTAssertEqual(model.getFormatStatusText(formatInfo: try XCTUnwrap(book.formats["EPUB"])), "Downloaded")
        XCTAssertEqual(model.getFormatStatusIcon(formatInfo: try XCTUnwrap(book.formats["EPUB"])), "checkmark.circle")
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
        XCTAssertNil(model.listVM)
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
        mockAppContainer.serverManager.addServer(server: other.library.server, libraries: [book.library, other.library])
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
        manager.clearCache(inShelfId: book.inShelfId)
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

    func testManagerReturnsCancelledForCancelledRequest() async throws {
        let request = CalibreBooksMetadataRequest(library: mockCalibreBook.library, books: [123], getAnnotations: false)
        let manager = mockAppContainer.bookManager
        let task = Task { await manager.getBooksMetadata(request: request) }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result[123], .cancelled)
    }

    func testViewModelSetup() throws {
        XCTAssertNotNil(viewModel.listVM)
        XCTAssertEqual(viewModel.listVM?.book.id, 123)
        XCTAssertEqual(viewModel.listVM?.book.title, "Test Book")
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
        XCTAssertEqual(viewModel.listVM?.book.title, "Updated Book")
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
        try FileManager.default.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("EPUB".utf8).write(to: savedURL)
        let delegate = BookFormatDownloadDelegate(download: download, manager: mockAppContainer.downloadManager)
        delegate.isFileExist = true
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
        failed.isFileExist = true
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

    func testSuccessfulSignalWithMissingFileDoesNotOpenAndAllowsRetry() async throws {
        let book = try makeDownloadReadBook()
        viewModel.readBook(book: book)
        let download = try controlledDownload(for: book)
        let delegate = BookFormatDownloadDelegate(download: download, manager: mockAppContainer.downloadManager)
        delegate.isFileExist = true
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
    private func controlledDownload(for book: CalibreBook) throws -> BookFormatDownload {
        let manager = mockAppContainer.downloadManager
        var download = try XCTUnwrap(manager.activeDownloads.values.first { $0.book.inShelfId == book.inShelfId && $0.isActive })
        let originalTask = download.downloadTask
        download.downloadTask = DetailDownloadTask(url: download.sourceURL)
        manager.activeDownloads[download.sourceURL] = download
        originalTask?.cancel()
        return download
    }

    private func completeReadDownload(_ download: BookFormatDownload) async throws {
        try FileManager.default.createDirectory(at: download.savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("EPUB".utf8).write(to: download.savedURL)
        let delegate = BookFormatDownloadDelegate(download: download, manager: mockAppContainer.downloadManager)
        delegate.isFileExist = true
        delegate.urlSession(URLSession.shared, task: try XCTUnwrap(download.downloadTask), didCompleteWithError: nil)
        await Task.yield()
        await waitUntil { self.mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion != nil }
        XCTAssertNotNil(mockAppContainer.downloadManager.activeDownloads[download.sourceURL]?.completion)
        withExtendedLifetime(delegate) {}
    }
    
    func testParseManifestToTOCSuccess() throws {
        let jsonString = "{\"toc\": {\"children\": [{\"title\": \"Chapter 1\"}, {\"title\": \"Chapter 2\"}]}}"
        let data = jsonString.data(using: .utf8)!
        viewModel.parseManifestToTOC(json: data)
        XCTAssertEqual(viewModel.previewViewModel.toc, "Chapter 1\nChapter 2\n", "TOC should be correctly parsed from manifest JSON")
    }
    
    func testParseManifestToTOCWaiting() throws {
        let jsonString = "{\"job_status\": \"waiting\"}"
        let data = jsonString.data(using: .utf8)!
        viewModel.parseManifestToTOC(json: data)
        XCTAssertEqual(viewModel.previewViewModel.toc, "Generating TOC, Please try again later", "Should show generating message when job is waiting")
    }
    
    func testParseManifestToTOCInvalidJSON() throws {
        let data = "Invalid JSON".data(using: .utf8)!
        viewModel.parseManifestToTOC(json: data)
        #if DEBUG
        XCTAssertEqual(viewModel.previewViewModel.toc, "Invalid JSON", "Should fallback to raw string for invalid JSON in DEBUG")
        #else
        XCTAssertEqual(viewModel.previewViewModel.toc, "Without TOC", "Should fallback to Without TOC for invalid JSON")
        #endif
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
        XCTAssertEqual(viewModel.listVM?.book.inShelfId, mockCalibreBook.inShelfId)
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
    
    func testGetFormatStatusTextAndIcon() throws {
        var formatInfo = FormatInfo(filename: "test.epub", serverSize: 100, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        XCTAssertEqual(viewModel.getFormatStatusText(formatInfo: formatInfo), "Not cached")
        
        formatInfo.cached = true
        formatInfo.cacheSize = 100
        XCTAssertEqual(viewModel.getFormatStatusText(formatInfo: formatInfo), "Up to date")
        XCTAssertEqual(viewModel.getFormatStatusIcon(formatInfo: formatInfo), "hand.thumbsup")
        
        formatInfo.cacheMTime = formatInfo.serverMTime.addingTimeInterval(-120)
        XCTAssertEqual(viewModel.getFormatStatusText(formatInfo: formatInfo), "Server has update")
        XCTAssertEqual(viewModel.getFormatStatusIcon(formatInfo: formatInfo), "hand.thumbsdown")
    }

    func testDownloadInteraction() throws {
        var book = mockCalibreBook!
        book.formats = ["EPUB": FormatInfo(selected: nil, filename: "book.epub", serverSize: 1024, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)]
        
        XCTAssertFalse(viewModel.isFormatDownloading(book: book, format: .EPUB))
        viewModel.cacheFormat(book: book, format: .EPUB)
        
        viewModel.cancelDownload(book: book, format: .EPUB)
        XCTAssertFalse(viewModel.isFormatDownloading(book: book, format: .EPUB))
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
        XCTAssertEqual(viewModel.previewViewModel.toc, "Initializing")

        await waitUntil {
            self.viewModel.previewViewModel.toc == "Intro\n"
        }
        XCTAssertEqual(viewModel.previewViewModel.toc, "Intro\n")
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
        XCTAssertEqual(viewModel.refreshState, .synced)
        XCTAssertEqual(viewModel.calibreBook?.title, "Refreshed Title")
        XCTAssertEqual(viewModel.listVM?.book.title, "Refreshed Title")
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
        let detailVM = ReadingPositionDetailViewModel(container: mockAppContainer, listModel: listViewModel, position: position)
        
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
        sessions: [BookDeviceReadingPositionHistory] = []
    ) -> ReadingPositionHistoryViewModel {
        let bookRepository = MockBookRepository()
        bookRepository.getBookReturn = mockBook
        mockAppContainer.bookRepository = bookRepository

        let readingPositionRepository = MockReadingPositionRepository()
        readingPositionRepository.getPositionsReturn = positions
        readingPositionRepository.positionHistoryReturn = sessions
        mockAppContainer.readingPositionRepository = readingPositionRepository
        // The history list keeps only sessions of books on the shelf.
        mockAppContainer.booksInShelf[mockBook.inShelfId] = mockBook

        return ReadingPositionHistoryViewModel(container: mockAppContainer, library: mockBook.library, bookId: mockBook.id)
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
        let detailVM = ReadingPositionDetailViewModel(container: mockAppContainer, listModel: listViewModel, position: position)
        detailVM.selectedFormatReader = .ReadiumEPUB

        detailVM.readSelectedFormat()

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

        historyVM.loadData()

        XCTAssertTrue(historyVM.isBookMode)
        XCTAssertEqual(historyVM.navigationTitle, "Reading History")
        XCTAssertEqual(historyVM.deviceSections.map(\.deviceName), [mockAppContainer.deviceName, "other-device"])
        XCTAssertEqual(historyVM.deviceSections.map(\.isThisDevice), [true, false])

        let latestRow = try XCTUnwrap(historyVM.deviceSections.first?.rows.first)
        XCTAssertEqual(latestRow.title, "Chapter 3")
        XCTAssertNil(latestRow.detail)
        XCTAssertFalse(latestRow.percentText.isEmpty)
        XCTAssertTrue(latestRow.canContinue)
    }

    func testHistoryViewModelBuildsLocalSessionRows() throws {
        let now = Date()
        let start = max(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-1800))
        let endPosition = TestFixtures.makeReadingPosition(
            id: mockAppContainer.deviceName,
            lastReadChapter: "Chapter 4",
            epoch: now.timeIntervalSince1970
        )
        let session = BookDeviceReadingPositionHistory(
            bookId: "\(mockBook.library.key) - \(mockBook.id)",
            startDatetime: start,
            startPosition: nil,
            endPosition: endPosition
        )
        let historyVM = makeHistoryViewModel(positions: [endPosition], sessions: [session])

        historyVM.loadData()

        XCTAssertEqual(historyVM.sessionRows.count, 1)
        XCTAssertEqual(historyVM.sessionRows.first?.chapter, "Chapter 4")
        XCTAssertFalse(historyVM.sessionRows.first?.durationText.isEmpty ?? true)
        XCTAssertEqual(historyVM.readingStatistics.count, ReadingPositionHistoryViewModel.limitDays + 1)
        XCTAssertEqual(historyVM.chartDayLabels().last, "Today")
    }

    func testHistoryViewModelContinueReadingRowOpensReader() throws {
        try makeCachedEPUB()
        let historyVM = makeHistoryViewModel(positions: [
            TestFixtures.makeReadingPosition(id: "device-1", lastReadChapter: "Chapter 5")
        ])
        historyVM.loadData()
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
        historyVM.loadData()
        let row = try XCTUnwrap(historyVM.deviceSections.first?.rows.first)
        XCTAssertFalse(row.canContinue)

        historyVM.continueReading(row, targetWorkspaceID: nil)

        XCTAssertEqual(historyVM.alertItem?.id, "Selected Format Not Cached")
        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
    }

    func testHistoryViewModelDismissDetailKeepsDisplayedPositionForThePopAnimation() throws {
        let historyVM = makeHistoryViewModel(positions: [])
        let position = TestFixtures.makeReadingPosition(id: "device-1")

        historyVM.showDetail(for: position)
        XCTAssertEqual(historyVM.detailPosition, position)
        XCTAssertEqual(historyVM.displayedDetailPosition, position)

        historyVM.dismissDetail()
        XCTAssertNil(historyVM.detailPosition)
        XCTAssertEqual(historyVM.displayedDetailPosition, position)
    }

    /// A reader above History or a finished download doesn't make the page appear again, so it
    /// reloads on book updates while shown.
    func testHistoryViewModelReloadsWhenBooksUpdate() async throws {
        let historyVM = makeHistoryViewModel(positions: [])
        historyVM.loadData()
        XCTAssertTrue(historyVM.deviceSections.isEmpty)
        await historyVM.observeChanges()

        let repository = try XCTUnwrap(mockAppContainer.readingPositionRepository as? MockReadingPositionRepository)
        repository.getPositionsReturn = [TestFixtures.makeReadingPosition(id: "device-1", lastReadChapter: "Chapter 6")]
        await mockAppContainer.publishCalibreUpdate(.shelf)

        let deadline = Date().addingTimeInterval(10)
        while historyVM.deviceSections.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(historyVM.deviceSections.first?.rows.first?.title, "Chapter 6")
    }

    func testHistoryViewModelStatisticsModeHasNoDeviceSections() throws {
        let historyVM = ReadingPositionHistoryViewModel(container: mockAppContainer, library: nil, bookId: nil)

        historyVM.loadData()

        XCTAssertFalse(historyVM.isBookMode)
        XCTAssertEqual(historyVM.navigationTitle, "Reading Statistics")
        XCTAssertTrue(historyVM.deviceSections.isEmpty)
        XCTAssertTrue(historyVM.sessionRows.isEmpty)
    }

    func testDetailViewModelReadSelectedFormatOpensReaderPresentation() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        try makeCachedEPUB()
        let detailVM = ReadingPositionDetailViewModel(container: mockAppContainer, listModel: listViewModel, position: position)

        detailVM.readSelectedFormat()

        XCTAssertNil(detailVM.alertItem, "readSelectedFormat raised alert: \(detailVM.alertItem?.id ?? "")")
        let presentation = mockAppContainer.sessionManager.activeReaderPresentation
        XCTAssertEqual(presentation?.book.inShelfId, mockBook.inShelfId)
        XCTAssertEqual(presentation?.source, .readingPosition)
        XCTAssertEqual(presentation?.readerInfo.position.id, position.id)
    }
    
    func testHistoryViewModelLoadData() throws {
        let historyVM = ReadingPositionHistoryViewModel(container: mockAppContainer, library: mockBook.library, bookId: mockBook.id)
        XCTAssertEqual(historyVM.maxMinutes, 0)
        
        historyVM.loadData()
        
        XCTAssertNotNil(historyVM.readingStatistics)
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

        let historyVM = ReadingPositionHistoryViewModel(container: mockAppContainer, library: mockBook.library, bookId: mockBook.id)
        historyVM.loadData()

        XCTAssertTrue(bookRepository.getBookCalled)
        XCTAssertEqual(bookRepository.getBookBookIdParam, mockBook.id)
        XCTAssertEqual(bookRepository.getBookLibraryParam, mockBook.library)
        XCTAssertTrue(readingPositionRepository.debugPositionsCalled)
        XCTAssertEqual(historyVM.listViewModel?.book.id, mockBook.id)
        XCTAssertEqual(historyVM.debugReadingPositions.first?.id, "debug-device")
    }
}

class ActivityListViewModelTests: XCTestCase {
    var mockAppContainer: AppContainer!
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ActivityListViewModelTests")
    }
    
    override func tearDownWithError() throws {
        mockAppContainer = nil
    }
    
    func testInitialization() throws {
        let repository = MockActivityLogRepository()
        let viewModel = ActivityListViewModel(container: mockAppContainer, activityLogRepository: repository)
        XCTAssertTrue(repository.fetchEntriesCalled)
        XCTAssertEqual(viewModel.activities.count, 0)
    }

    func testInitializationUsesRepositoryAndReceivesUpdates() async throws {
        let repository = MockActivityLogRepository()
        let initialEntry = ActivityLogUIEntry(
            id: "1",
            libraryName: "Library",
            bookTitle: "Book",
            type: "Sync",
            errMsg: "",
            startDateString: "start",
            finishDateString: "finish",
            startDateLongString: "start long",
            finishDateLongString: "finish long",
            endpointURL: "http://localhost",
            httpMethod: "GET",
            httpBodyString: nil
        )
        repository.fetchEntriesReturn = [initialEntry]

        let viewModel = ActivityListViewModel(
            container: mockAppContainer,
            libraryId: "library-id",
            bookId: 7,
            activityLogRepository: repository
        )

        XCTAssertTrue(repository.fetchEntriesCalled)
        XCTAssertEqual(repository.fetchEntriesLibraryIdParam, "library-id")
        XCTAssertEqual(repository.fetchEntriesBookIdParam, 7)
        XCTAssertEqual(viewModel.activities, [initialEntry])
        // The updates reach the view model on the main actor. As the suite's first class, this
        // runs while a freshly installed test host is still starting on a CI runner.
        let deadline = Date().addingTimeInterval(10)
        while repository.observeEntriesSubscriberCount == 0 && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(repository.observeEntriesCalled)
        XCTAssertEqual(repository.observeEntriesLibraryIdParam, "library-id")
        XCTAssertEqual(repository.observeEntriesBookIdParam, 7)
        XCTAssertEqual(repository.observeEntriesSubscriberCount, 1)

        let updatedEntry = ActivityLogUIEntry(
            id: "2",
            libraryName: "Library 2",
            bookTitle: "Book 2",
            type: "Error",
            errMsg: "boom",
            startDateString: "s2",
            finishDateString: "f2",
            startDateLongString: "sl2",
            finishDateLongString: "fl2",
            endpointURL: "http://localhost/2",
            httpMethod: "POST",
            httpBodyString: "{}"
        )
        repository.sendObservedEntries([updatedEntry])
        // The update is applied on the main actor, which the starting test host can hold for over
        // 10 s on a fresh CI runner. Start the deadline once the main actor runs, so the wait
        // measures delivery rather than the host's startup.
        await MainActor.run {}
        let updateDeadline = Date().addingTimeInterval(10)
        while viewModel.activities != [updatedEntry] && Date() < updateDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(viewModel.activities, [updatedEntry])
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

        let viewModel = LibraryViewModel(container: container, library: library, libraryRepository: repository)
        repository.updateLibraryFlagsCalled = false

        viewModel.setDiscoverable(!library.discoverable)

        XCTAssertTrue(repository.updateLibraryFlagsCalled)
        XCTAssertEqual(repository.updateLibraryFlagsIdParam, library.id)
        XCTAssertEqual(repository.updateLibraryFlagsDiscoverableParam, !library.discoverable)
        // The manager's copy too, which it saves whole.
        XCTAssertEqual(container.libraryManager.calibreLibraries[library.id]?.discoverable, !library.discoverable)
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

    override func persistMetadataEntries(library: CalibreLibrary, bookIds: [Int32],
                                        entries: [String: CalibreBookEntry?], json: NSDictionary,
                                        includeAnnotationBooks: Bool) -> BookMetadataPersistenceResult {
        if !blockAfterCommit { atBoundary() }
        let result = super.persistMetadataEntries(library: library, bookIds: bookIds,
            entries: entries, json: json, includeAnnotationBooks: includeAnnotationBooks)
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
