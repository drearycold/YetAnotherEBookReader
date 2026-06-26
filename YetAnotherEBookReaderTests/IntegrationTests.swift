import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class IntegrationTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()
    
    override func setUp() async throws {
        try await super.setUp()
        cancellables = []
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        ModelData.shared = nil
        try await super.tearDown()
    }
    
    private func makeModelData(id: String) -> ModelData {
        let config = Realm.Configuration(
            inMemoryIdentifier: id,
            schemaVersion: 140,
            migrationBlock: { _, _ in }
        )
        DatabaseService.shared.setup(conf: config)
        let modelData = ModelData(mock: true)
        modelData.realmConf = config
        return modelData
    }
    
    func testDatabaseInitialization() throws {
        let config = Realm.Configuration(
            inMemoryIdentifier: "IntegrationTests-DBInit-\(UUID().uuidString)",
            schemaVersion: 140,
            migrationBlock: { _, _ in }
        )
        DatabaseService.shared.setup(conf: config)
        
        let modelData = ModelData(mock: true)
        modelData.realmConf = config
        
        try modelData.tryInitializeDatabase { status in
            // DB init status callback
        }
        
        XCTAssertTrue(modelData.isDatabaseReady)
        XCTAssertNotNil(modelData.realm)
    }
    
    func testFullReadingFlow() async throws {
        let modelData = makeModelData(id: "IntegrationTests-ReadingFlow-\(UUID().uuidString)")
        
        let server = CalibreServer(uuid: UUID(), name: "Read Server", baseUrl: "http://read-server", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "read_lib", name: "Read Lib")
        modelData.serverManager.addServer(server: server, libraries: [library])
        
        var book = CalibreBook(id: 789, library: library)
        book.title = "Read Flow Book"
        modelData.bookRepository.saveBook(book)
        
        let initialPos = BookDeviceReadingPosition(
            id: modelData.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue,
            maxPage: 100,
            lastReadPage: 1,
            lastReadChapter: "Chapter 1",
            lastChapterProgress: 0.0,
            lastProgress: 0.0,
            furthestReadPage: 1,
            furthestReadChapter: "Chapter 1",
            lastPosition: [1, 0, 0],
            cfi: "cfi-1",
            epoch: Date().timeIntervalSince1970
        )
        
        let readerInfo = ReaderInfo(
            deviceName: modelData.deviceName,
            url: URL(fileURLWithPath: "/tmp/book.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: initialPos
        )
        
        // Start reading session
        modelData.sessionManager.readingBook = book
        modelData.sessionManager.readerInfo = readerInfo
        XCTAssertEqual(modelData.sessionManager.readingBook?.id, book.id)
        
        // Update reading position
        let updatedPos = BookDeviceReadingPosition(
            id: modelData.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue,
            maxPage: 100,
            lastReadPage: 12,
            lastReadChapter: "Chapter 2",
            lastChapterProgress: 0.1,
            lastProgress: 0.12,
            furthestReadPage: 12,
            furthestReadChapter: "Chapter 2",
            lastPosition: [12, 0, 0],
            cfi: "cfi-12",
            epoch: Date().timeIntervalSince1970
        )
        modelData.readingPositionRepository.savePosition(updatedPos, forBookId: book.bookPrefId)
        modelData.sessionManager.updateCurrentPosition(alertDelegate: nil)
        
        // End reading session
        await modelData.sessionManager.handleBookReaderClosed(book: book, lastPosition: initialPos)
        modelData.sessionManager.readingBook = nil
        XCTAssertNil(modelData.sessionManager.readingBook)
        
        // Retrieve and assert saved position
        let retrieved = modelData.readingPositionRepository.getPosition(forBookId: book.bookPrefId, deviceName: modelData.deviceName)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.lastReadPage, 12)
        XCTAssertEqual(retrieved?.cfi, "cfi-12")
    }
    
    func testSearchToDownloadFlow() async throws {
        let modelData = makeModelData(id: "IntegrationTests-SearchDownload-\(UUID().uuidString)")
        
        let server = CalibreServer(uuid: UUID(), name: "Search Server", baseUrl: "http://search-server", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "search_lib", name: "Search Lib")
        modelData.serverManager.addServer(server: server, libraries: [library])
        
        var book = CalibreBook(id: 456, library: library)
        book.title = "Search Download Book"
        book.formats = ["EPUB": FormatInfo(selected: nil, filename: "book.epub", serverSize: 100, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)]
        
        // Setup URL session stubbing for download
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        modelData.downloadManager.sessionConfiguration = sessionConfig
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("epub-content".utf8))
        }
        
        guard let savedURL = getSavedUrl(book: book, format: .EPUB) else {
            return XCTFail("Unable to get saved URL")
        }
        defer {
            try? FileManager.default.removeItem(at: savedURL)
        }
        
        let result = modelData.downloadManager.startDownloadNew(book, format: .EPUB, overwrite: true)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Download start failed with error: \(error)")
        }
        
        // Wait a bit for the mock download task to complete
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
    }
    
    func testServerSetupAndLibrarySync() async throws {
        let modelData = makeModelData(id: "IntegrationTests-Sync-\(UUID().uuidString)")
        
        let server = CalibreServer(uuid: UUID(), name: "Setup Server", baseUrl: "http://setup-server", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "setup_lib", name: "Setup Lib")
        
        // Add server and library
        modelData.serverManager.addServer(server: server, libraries: [library])
        
        // Assert they are in repository / Realm
        let savedServer = modelData.serverRepository.getAllServers().first(where: { $0.id == server.id })
        XCTAssertNotNil(savedServer)
        XCTAssertEqual(savedServer?.name, "Setup Server")
        
        let savedLib = modelData.libraryRepository.getLibrary(id: library.id)
        XCTAssertNotNil(savedLib)
        XCTAssertEqual(savedLib?.name, "Setup Lib")
    }
}
