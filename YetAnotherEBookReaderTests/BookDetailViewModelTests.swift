import XCTest
import SwiftUI
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

class BookDetailViewModelTests: XCTestCase {
    
    var viewModel: BookDetailViewModel!
    var mockModelData: ModelData!
    var mockBookRealm: CalibreBookRealm!
    var mockCalibreBook: CalibreBook!
    
    var originalModelDataShared: ModelData?
    var cancellables = Set<AnyCancellable>()
    
    override func setUpWithError() throws {
        originalModelDataShared = ModelData.shared
        mockModelData = ModelData(mock: true)
        ModelData.shared = mockModelData
        viewModel = BookDetailViewModel(modelData: mockModelData)
        
        guard let library = mockModelData.calibreLibraries.first?.value else {
            XCTFail("No mock library found in mockModelData")
            return
        }
        
        mockBookRealm = CalibreBookRealm()
        mockBookRealm.serverUUID = library.server.uuid.uuidString
        mockBookRealm.libraryName = library.name
        mockBookRealm.idInLib = 123
        mockBookRealm.title = "Test Book"
        mockBookRealm.updatePrimaryKey()
        
        mockCalibreBook = CalibreBook(id: 123, library: library)
        mockCalibreBook.title = "Test Book"
        
        try! mockModelData.realm.write {
            mockModelData.realm.add(mockBookRealm, update: .modified)
        }
        
        viewModel.setup(bookId: mockBookRealm.primaryKey!)
        clearReadingPositions()
    }

    override func tearDownWithError() throws {
        if let library = mockModelData?.calibreLibraries.first?.value {
            try? mockModelData?.realm.write {
                if let serverRealm = mockModelData?.realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
                    serverRealm.dsreaderHelper = nil
                }
            }
        }
        clearReadingPositions()
        
        ModelData.shared = originalModelDataShared
        viewModel = nil
        mockModelData = nil
        mockBookRealm = nil
        mockCalibreBook = nil
        cancellables.removeAll()
    }
    
    private func clearReadingPositions() {
        guard let calibreBook = mockCalibreBook else { return }
        let bookId = calibreBook.bookPrefId
        let components = bookId.components(separatedBy: " - ")
        if components.count > 1 {
            let libraryKey = components[0]
            if let library = mockModelData?.calibreLibraries.values.first(where: { $0.key == libraryKey }),
               let realm = try? Realm(configuration: BookAnnotation.getBookPreferenceServerConfig(library.server)) {
                try? realm.write {
                    realm.delete(realm.objects(BookDeviceReadingPositionRealm.self))
                }
            }
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

        try mockModelData.realm.write {
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
        XCTAssertNotNil(mockModelData.readerInfo, "Reader info should be populated when reading an in-shelf book")
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
        mockModelData.updatingMetadata = true
        XCTAssertTrue(viewModel.updatingMetadata)
    }

    func testPushAndPopPresenting() throws {
        var presenting = false
        let binding = Binding<Bool>(
            get: { presenting },
            set: { presenting = $0 }
        )
        
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        viewModel.pushPresenting(binding)
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        
        viewModel.popPresenting()
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
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
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.presentingReadingSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.presentingReadingSheet = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.presentingPreviewSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.presentingPreviewSheet = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.activityListViewPresenting = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.activityListViewPresenting = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.readingPositionHistoryViewPresenting = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.readingPositionHistoryViewPresenting = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
    }

    func testPresentationSheetPropertiesBindingInteractions() throws {
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.presentingReadingSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        
        let binding = mockModelData.presentingStack.last
        XCTAssertNotNil(binding)
        XCTAssertTrue(binding?.wrappedValue ?? false)
        
        // Dismiss via binding (e.g. SwiftUI sheet dismissal)
        binding?.wrappedValue = false
        XCTAssertFalse(viewModel.presentingReadingSheet)
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
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
        
        guard let library = mockModelData.calibreLibraries.first?.value else { return }
        
        try! mockModelData.realm.write {
            if let serverRealm = mockModelData.realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
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
        guard let library = mockModelData.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockModelData.realm.write {
            if let serverRealm = mockModelData.realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
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
        mockModelData.readingPositionRepository.savePosition(devicePosition, forBookId: mockCalibreBook.bookPrefId)
        
        let otherPosition = BookDeviceReadingPosition(
            id: "other-device",
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 5,
            lastProgress: 30.0,
            epoch: Date().timeIntervalSince1970
        )
        mockModelData.readingPositionRepository.savePosition(otherPosition, forBookId: mockCalibreBook.bookPrefId)
        
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
        guard let library = mockModelData.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockModelData.realm.write {
            if let serverRealm = mockModelData.realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
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
        mockModelData.readingPositionRepository.savePosition(otherPosition, forBookId: mockCalibreBook.bookPrefId)
        
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
        guard let library = mockModelData.calibreLibraries.first?.value else {
            XCTFail("No mock library found")
            return
        }
        try! mockModelData.realm.write {
            if let serverRealm = mockModelData.realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.uuid.uuidString) {
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
        mockModelData.readingPositionRepository.savePosition(position, forBookId: mockCalibreBook.bookPrefId)
        
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
}

class ReadingPositionViewModelTests: XCTestCase {
    var mockModelData: ModelData!
    var listViewModel: ReadingPositionListViewModel!
    var mockBook: CalibreBook!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
        
        let library = CalibreLibrary(server: CalibreServer(uuid: UUID(), name: "MockServer", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "lib1", name: "Mock Library")
        mockBook = CalibreBook(id: 123, library: library)
        mockBook.title = "Test Book"
        
        listViewModel = ReadingPositionListViewModel(modelData: mockModelData, book: mockBook, positions: [])
    }
    
    override func tearDownWithError() throws {
        listViewModel = nil
        mockBook = nil
        mockModelData = nil
    }
    
    func testDetailViewModelInitialization() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        let detailVM = ReadingPositionDetailViewModel(modelData: mockModelData, listModel: listViewModel, position: position)
        
        XCTAssertEqual(detailVM.position.id, "device-1")
        XCTAssertEqual(detailVM.selectedFormatReader, .YabrEPUB)
        XCTAssertEqual(detailVM.selectedFormat, .EPUB)
    }
    
    func testDetailViewModelPresentingSheet() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        let detailVM = ReadingPositionDetailViewModel(modelData: mockModelData, listModel: listViewModel, position: position)
        
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        detailVM.presentingReadSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        detailVM.presentingReadSheet = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
    }
    
    func testHistoryViewModelLoadData() throws {
        let historyVM = ReadingPositionHistoryViewModel(modelData: mockModelData, library: mockBook.library, bookId: mockBook.id)
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
        mockModelData.readingPositionRepository = repository

        let historyVM = ReadingPositionHistoryViewModel(modelData: mockModelData, library: mockBook.library, bookId: mockBook.id)
        historyVM.loadData()

        XCTAssertTrue(repository.historyBookCalled)
        XCTAssertEqual(repository.historyBookIdParam, mockBook.id)
        XCTAssertTrue(repository.debugPositionsCalled)
        XCTAssertEqual(historyVM.listViewModel?.book.id, mockBook.id)
        XCTAssertEqual(historyVM.debugReadingPositions.first?.id, "debug-device")
    }
}

class ActivityListViewModelTests: XCTestCase {
    var mockModelData: ModelData!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
    }
    
    override func tearDownWithError() throws {
        mockModelData = nil
    }
    
    func testInitialization() throws {
        let repository = MockActivityLogRepository()
        let viewModel = ActivityListViewModel(modelData: mockModelData, activityLogRepository: repository)
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
            modelData: mockModelData,
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
        let modelData = ModelData(mock: true)
        let library = try XCTUnwrap(modelData.calibreLibraries.first?.value)
        let repository = MockLibraryRepository()
        repository.getLibraryReturn = library

        let viewModel = LibraryViewModel(modelData: modelData, library: library, libraryRepository: repository)

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
        let modelData = ModelData(mock: true)
        let library = try XCTUnwrap(modelData.calibreLibraries.first?.value)
        let repository = MockLibraryRepository()
        repository.getLibraryReturn = library

        let viewModel = LibraryViewModel(modelData: modelData, library: library, libraryRepository: repository)
        repository.updateLibraryFlagsCalled = false

        viewModel.discoverable = !library.discoverable
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(repository.updateLibraryFlagsCalled)
        XCTAssertEqual(repository.updateLibraryFlagsIdParam, library.id)
        XCTAssertEqual(repository.updateLibraryFlagsDiscoverableParam, !library.discoverable)
    }
}

class ReadingPositionRepositoryThreadingTests: XCTestCase {
    var mockModelData: ModelData!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
        try! mockModelData.realm.write {
            mockModelData.realm.deleteAll()
        }
    }
    
    override func tearDownWithError() throws {
        mockModelData = nil
    }
    
    func testGetPositionsCanReadFromBackgroundQueue() throws {
        let library = mockModelData.calibreLibraries.first?.value ?? CalibreLibrary(
            server: CalibreServer(uuid: UUID(), name: "MockServer", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""),
            key: "lib1",
            name: "Mock Library"
        )
        
        mockModelData.calibreLibraries[library.id] = library
        
        var book = CalibreBook(id: 456, library: library)
        book.title = "Threading Test Book"
        
        let position = BookDeviceReadingPosition(
            id: "thread-test-device",
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 7,
            lastProgress: 42.0,
            epoch: Date().timeIntervalSince1970
        )
        mockModelData.readingPositionRepository.savePosition(position, forBookId: book.bookPrefId)
        
        let expectation = expectation(description: "Background queue can read reading positions")
        let queue = DispatchQueue(label: "reading-position-thread-test")
        
        queue.async {
            let positions = self.mockModelData.readingPositionRepository.getPositions(forBookId: book.bookPrefId)
            XCTAssertTrue(positions.contains(where: { $0.id == "thread-test-device" }))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}
