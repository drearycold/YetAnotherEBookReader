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
            autoUpdateOnly: false,
            incremental: false
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
        
        try! mockAppContainer.realm!.write {
            mockAppContainer.realm!.add(mockBookRealm, update: .modified)
        }
        
        viewModel.setup(bookId: mockBookRealm.primaryKey!)
        clearReadingPositions()
    }

    override func tearDownWithError() throws {
        if let library = mockAppContainer?.calibreLibraries.first?.value {
            try? mockAppContainer?.realm!.write {
                if let serverRealm = mockAppContainer?.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
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

    func testViewModelSetup() throws {
        XCTAssertNotNil(viewModel.listVM)
        XCTAssertEqual(viewModel.listVM?.book.id, 123)
        XCTAssertEqual(viewModel.listVM?.book.title, "Test Book")
    }

    func testSetupObservesBookValueTypeUpdates() throws {
        let expectation = expectation(description: "book publisher update propagates to view model")
        viewModel.$calibreBook
            .compactMap { $0?.title }
            .dropFirst()
            .sink { title in
                if title == "Updated Book" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        try mockAppContainer.realm!.write {
            mockBookRealm.title = "Updated Book"
        }

        wait(for: [expectation], timeout: 2.0)
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
        viewModel.readBook(book: mockCalibreBook)
        XCTAssertNotNil(mockAppContainer.sessionManager.readerInfo, "Reader info should be populated when reading an in-shelf book")
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
        XCTAssertTrue(viewModel.updatingMetadata)
    }

    func testPushAndPopPresenting() throws {
        var presenting = false
        let binding = Binding<Bool>(
            get: { presenting },
            set: { presenting = $0 }
        )
        
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
        viewModel.pushPresenting(binding)
        XCTAssertEqual(mockAppContainer.presentingStack.count, 1)
        
        viewModel.popPresenting()
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
    }

    func testConvertBookRealm() throws {
        let nonQueryableBook = CalibreBookRealm()
        nonQueryableBook.serverUUID = "non-existent-uuid"
        nonQueryableBook.libraryName = "Non Existent Library"
        nonQueryableBook.idInLib = 999
        nonQueryableBook.title = "Non Queryable Book"
        nonQueryableBook.updatePrimaryKey()
        
        let result = viewModel.convert(bookRealm: nonQueryableBook)
        XCTAssertNil(result, "Should return nil if library is not queryable in mock model data")
    }

    func testPresentationSheetProperties() throws {
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
        
        viewModel.presentingReadingSheet = true
        XCTAssertEqual(mockAppContainer.presentingStack.count, 1)
        viewModel.presentingReadingSheet = false
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
        
        viewModel.presentingPreviewSheet = true
        XCTAssertEqual(mockAppContainer.presentingStack.count, 1)
        viewModel.presentingPreviewSheet = false
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
        
        viewModel.activityListViewPresenting = true
        XCTAssertEqual(mockAppContainer.presentingStack.count, 1)
        viewModel.activityListViewPresenting = false
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
        
        viewModel.readingPositionHistoryViewPresenting = true
        XCTAssertEqual(mockAppContainer.presentingStack.count, 1)
        viewModel.readingPositionHistoryViewPresenting = false
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
    }

    func testPresentationSheetPropertiesBindingInteractions() throws {
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
        
        viewModel.presentingReadingSheet = true
        XCTAssertEqual(mockAppContainer.presentingStack.count, 1)
        
        let binding = mockAppContainer.presentingStack.last
        XCTAssertNotNil(binding)
        XCTAssertTrue(binding?.wrappedValue ?? false)
        
        // Dismiss via binding (e.g. SwiftUI sheet dismissal)
        binding?.wrappedValue = false
        XCTAssertFalse(viewModel.presentingReadingSheet)
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
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
        
        let helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        
        guard let library = mockCalibreBook?.library else { return }
        
        try! mockAppContainer.realm!.write {
            if let serverRealm = mockAppContainer.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = helper
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
        
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .goodreadsReadDate(expectedString))
    }
    
    func testReadingProgressSummary_GoodreadsProgress() throws {
        setupMockGoodreadsSync(readingProgressColumn: "#progress")
        mockCalibreBook.userMetadatas = ["progress": 85]
        
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .goodreadsProgress("85"))
    }
    
    func testReadingProgressSummary_LocalProgress_CurrentDevice() throws {
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: nil,
            count_pages_prefs: nil,
            goodreads_sync_prefs: nil
        )
        let helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        guard let library = mockAppContainer.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockAppContainer.realm!.write {
            if let serverRealm = mockAppContainer.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = helper
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
        
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .localProgress(percent: 75.0, device: viewModel.deviceName))
    }
    
    func testReadingProgressSummary_LocalProgress_Fallback() throws {
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: nil,
            count_pages_prefs: nil,
            goodreads_sync_prefs: nil
        )
        let helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        guard let library = mockAppContainer.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockAppContainer.realm!.write {
            if let serverRealm = mockAppContainer.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = helper
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
        
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertEqual(summary, .localProgress(percent: 30.0, device: "other-device"))
    }
    
    func testReadingProgressSummary_None() throws {
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: nil,
            count_pages_prefs: nil,
            goodreads_sync_prefs: nil
        )
        let helper = CalibreServerDSReaderHelper(port: 8080)
        helper.configuration = config
        guard let library = mockAppContainer.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockAppContainer.realm!.write {
            if let serverRealm = mockAppContainer.realm!.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                serverRealm.dsreaderHelper = helper
            }
        }
        
        let summary = viewModel.getReadingProgressSummary(for: mockCalibreBook)
        XCTAssertNil(summary)
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
        
        XCTAssertTrue(viewModel.hasReadingHistory(for: mockCalibreBook))
    }
    
    func testIsFormatDownloading() throws {
        let format = Format.EPUB
        XCTAssertFalse(viewModel.isFormatDownloading(bookId: 123, format: format))
        
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
        XCTAssertTrue(viewModel.isFormatDownloading(bookId: 123, format: format))
        XCTAssertFalse(viewModel.isFormatDownloading(bookId: 456, format: format))
        
        viewModel.activeDownloads.removeAll()
    }
    
    func testGetActiveDownload() throws {
        let format = Format.EPUB
        XCTAssertNil(viewModel.getActiveDownload(bookId: 123, format: format))
        
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
        
        let retrieved = viewModel.getActiveDownload(bookId: 123, format: format)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.book.id, 123)
        XCTAssertEqual(retrieved?.format, format)
        
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
        
        XCTAssertFalse(viewModel.isFormatDownloading(bookId: book.id, format: .EPUB))
        viewModel.cacheFormat(book: book, format: .EPUB)
        
        viewModel.cancelDownload(book: book, format: .EPUB)
        XCTAssertFalse(viewModel.isFormatDownloading(bookId: book.id, format: .EPUB))
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
            return (response, bookEntryJson.data(using: .utf8)!)
        }
        
        viewModel.refresh(book: book)

        await waitUntil {
            self.viewModel.calibreBook?.title == "Refreshed Title"
        }

        mockAppContainer.refreshDatabase()
        
        guard let realm = mockAppContainer.realm else {
            XCTFail("Realm is nil")
            return
        }
        
        XCTAssertEqual(viewModel.calibreBook?.title, "Refreshed Title")
        XCTAssertEqual(viewModel.listVM?.book.title, "Refreshed Title")
        XCTAssertEqual(
            realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: mockBookRealm.primaryKey!)?.title,
            "Refreshed Title"
        )
    }
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
    
    func testDetailViewModelPresentingSheet() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        let detailVM = ReadingPositionDetailViewModel(container: mockAppContainer, listModel: listViewModel, position: position)
        
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
        detailVM.presentingReadSheet = true
        XCTAssertEqual(mockAppContainer.presentingStack.count, 1)
        detailVM.presentingReadSheet = false
        XCTAssertEqual(mockAppContainer.presentingStack.count, 0)
    }
    
    func testHistoryViewModelLoadData() throws {
        let historyVM = ReadingPositionHistoryViewModel(container: mockAppContainer, library: mockBook.library, bookId: mockBook.id)
        XCTAssertEqual(historyVM.maxMinutes, 0)
        
        historyVM.loadData()
        
        XCTAssertNotNil(historyVM.readingStatistics)
    }

    func testHistoryViewModelUsesRepositoryForHistoryBookAndDebugPositions() throws {
        let repository = MockReadingPositionRepository()
        repository.historyBookReturn = mockBook
        repository.debugPositionsReturn = [
            BookDeviceReadingPosition(id: "debug-device", readerName: ReaderType.YabrEPUB.rawValue)
        ]
        mockAppContainer.readingPositionRepository = repository

        let historyVM = ReadingPositionHistoryViewModel(container: mockAppContainer, library: mockBook.library, bookId: mockBook.id)
        historyVM.loadData()

        XCTAssertTrue(repository.historyBookCalled)
        XCTAssertEqual(repository.historyBookIdParam, mockBook.id)
        XCTAssertTrue(repository.debugPositionsCalled)
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

    func testInitializationUsesRepositoryAndReceivesUpdates() throws {
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
        repository.observeEntriesSubject.send([updatedEntry])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(viewModel.activities, [updatedEntry])
    }
}

class LibraryViewModelTests: XCTestCase {
    func testInitializationReadsPersistedFlagsAndObservesUpdates() throws {
        let container = MockAppContainerFactory.makeContainer(testName: "LibraryViewModelTests")
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let repository = MockLibraryRepository()
        repository.getLibraryReturn = library

        let viewModel = LibraryViewModel(container: container, library: library, libraryRepository: repository)

        XCTAssertTrue(repository.getLibraryCalled)
        XCTAssertTrue(repository.observeLibraryCalled)

        var updatedLibrary = library
        updatedLibrary.discoverable = true
        updatedLibrary.autoUpdate = true
        repository.observeLibrarySubject.send(updatedLibrary)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(viewModel.discoverable)
        XCTAssertTrue(viewModel.autoUpdate)
    }

    func testFlagMutationsCallUpdateLibraryFlags() throws {
        let container = MockAppContainerFactory.makeContainer(testName: "LibraryViewModelTests")
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let repository = MockLibraryRepository()
        repository.getLibraryReturn = library

        let viewModel = LibraryViewModel(container: container, library: library, libraryRepository: repository)
        repository.updateLibraryFlagsCalled = false

        viewModel.discoverable = !library.discoverable
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(repository.updateLibraryFlagsCalled)
        XCTAssertEqual(repository.updateLibraryFlagsIdParam, library.id)
        XCTAssertEqual(repository.updateLibraryFlagsDiscoverableParam, !library.discoverable)
    }
}

class ReadingPositionRepositoryThreadingTests: XCTestCase {
    var mockAppContainer: AppContainer!
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ReadingPositionRepositoryThreadingTests")
        try! mockAppContainer.realm!.write {
            mockAppContainer.realm!.deleteAll()
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
