//
//  CalibreLibraryManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class CalibreLibraryManagerTests: XCTestCase {
    private var container: AppContainer!
    private var libraryManager: CalibreLibraryManager!
    private var library: CalibreLibrary!
    private var server: CalibreServer!
    private var databaseService: DatabaseService!
    private var libraryRepository: LibraryRepositoryProtocol!

    override func setUpWithError() throws {
        // Set up in-memory Realm configuration to isolate each test
        container = MockAppContainerFactory.makeContainer(testName: "CalibreLibraryManagerTests")
        
        libraryManager = container.libraryManager
        databaseService = container.databaseService
        libraryRepository = container.libraryRepository
        
        server = CalibreServer(
            uuid: UUID(),
            name: "Test Calibre Server",
            baseUrl: "http://localhost",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        container.serverManager.calibreServers[server.id] = server
        try? container.serverManager.updateServerRealm(server: server)
        
        library = CalibreLibrary(server: server, key: "test_lib", name: "Test Library")
        libraryManager.calibreLibraries[library.id] = library
        try? libraryRepository.saveLibrary(library)
        
        XCTAssertNotNil(server, "Mock server should be populated")
        XCTAssertNotNil(library, "Mock library should be populated")
    }

    override func tearDownWithError() throws {
        container = nil
        libraryManager = nil
        library = nil
        server = nil
        databaseService = nil
        libraryRepository = nil
        AppContainer.shared = nil
    }

    func testPopulateLibraries() throws {
        // Create a new mock library in repository
        let newLib = CalibreLibrary(server: server, key: "new_lib", name: "New Library")
        try libraryRepository.saveLibrary(newLib)
        
        // Clear in-memory dictionary
        libraryManager.calibreLibraries.removeAll()
        
        // Populate
        libraryManager.populateLibraries()
        
        // Assert
        XCTAssertNotNil(libraryManager.calibreLibraries[newLib.id])
        XCTAssertEqual(libraryManager.calibreLibraries[newLib.id]?.name, "New Library")
    }

    func testUpdateLibraryRealm() throws {
        var lib = library!
        lib.name = "Updated Library Name"
        
        try libraryManager.updateLibraryRealm(library: lib)
        
        let allLibs = libraryRepository.getAllLibraries()
        let updated = allLibs.first { $0.id == lib.id }
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.name, "Updated Library Name")
    }

    func testHideAndRestoreLibrary() throws {
        let libId = library.id
        
        // Hide
        libraryManager.hideLibrary(libraryId: libId)
        
        XCTAssertTrue(libraryManager.calibreLibraries[libId]?.hidden ?? false)
        XCTAssertFalse(libraryManager.calibreLibraries[libId]?.autoUpdate ?? true)
        
        // Verify in repository
        let allLibs = libraryRepository.getAllLibraries()
        let hiddenLib = allLibs.first { $0.id == libId }
        XCTAssertTrue(hiddenLib?.hidden ?? false)
        
        // Restore
        libraryManager.restoreLibrary(libraryId: libId)
        
        XCTAssertFalse(libraryManager.calibreLibraries[libId]?.hidden ?? true)
        XCTAssertEqual(libraryManager.calibreLibraries[libId]?.lastModified, Date(timeIntervalSince1970: 0))
        
        // Verify in repository
        let restoredLib = libraryRepository.getAllLibraries().first { $0.id == libId }
        XCTAssertFalse(restoredLib?.hidden ?? true)
    }

    func testQueryLibraryBookRealmCount() throws {
        let book = CalibreBook(id: 999, library: library)
        container.bookManager.updateBook(book: book)
        
        let count = libraryManager.queryLibraryBookRealmCount(library: library)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testUpdateServerLibraryInfo() throws {
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        
        let libraryMap = [
            "existingKey": "Updated Library Name",
            "newKey": "New Remote Library"
        ]
        
        let serverInfo = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: "http://localhost")!,
            reachable: true,
            probing: false,
            errorMsg: "",
            defaultLibrary: "existingKey",
            libraryMap: libraryMap,
            request: probeRequest
        )
        
        let existingLib = CalibreLibrary(server: server, key: "existingKey", name: "Old Name")
        libraryManager.calibreLibraries[existingLib.id] = existingLib
        try libraryRepository.saveLibrary(existingLib)
        
        libraryManager.updateServerLibraryInfo(serverInfo: serverInfo)
        
        XCTAssertEqual(libraryManager.calibreLibraries[existingLib.id]?.key, "existingKey")
        
        let newLibId = CalibreLibrary(server: server, key: "newKey", name: "New Remote Library").id
        XCTAssertNotNil(libraryManager.calibreLibraries[newLibId])
        XCTAssertEqual(libraryManager.calibreLibraries[newLibId]?.name, "New Remote Library")
    }

    func testProbeLibrarySuccess() async throws {
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        let jsonResponse = """
        {
            "total_num": 42,
            "sort_order": "asc",
            "num_books_without_search": 0,
            "offset": 0,
            "num": 0,
            "sort": "title",
            "base_url": "/ajax/search/test_lib",
            "query": "",
            "library_id": "test_lib",
            "book_ids": [],
            "vl": ""
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonResponse.data(using: .utf8)!)
        }
        
        let req = CalibreProbeLibraryRequest(library: library)
        let task = await libraryManager.probeLibrary(request: req)
        
        XCTAssertEqual(task.probeResult?.total_num, 42)
        
        let stagingInfo = libraryManager.calibreLibraryInfoStaging[library.id]
        XCTAssertNotNil(stagingInfo)
        XCTAssertEqual(stagingInfo?.totalNumber, 42)
        XCTAssertEqual(stagingInfo?.errorMessage, "Success")
    }

    func testProbeLibraryFailure() async throws {
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        let req = CalibreProbeLibraryRequest(library: library)
        let task = await libraryManager.probeLibrary(request: req)
        
        XCTAssertNil(task.probeResult)
        
        let stagingInfo = libraryManager.calibreLibraryInfoStaging[library.id]
        XCTAssertNotNil(stagingInfo)
        XCTAssertEqual(stagingInfo?.totalNumber, 0)
        XCTAssertEqual(stagingInfo?.errorMessage, "Failed")
    }

    func testRemoveLibrary() async throws {
        var book = CalibreBook(id: 777, library: library)
        book.inShelf = true
        container.bookManager.updateBook(book: book)
        container.bookManager.booksInShelf[book.inShelfId] = book
        
        try libraryRepository.saveLibrary(library)
        
        let dbLibBefore = libraryRepository.getAllLibraries().first { $0.id == library.id }
        XCTAssertNotNil(dbLibBefore)
        
        await libraryManager.removeLibrary(library: library)
        
        let dbLibAfter = libraryRepository.getAllLibraries().first { $0.id == library.id }
        XCTAssertNil(dbLibAfter)
        
        XCTAssertNil(container.bookManager.booksInShelf[book.inShelfId])
        XCTAssertFalse(libraryManager.librarySyncStatus[library.id]?.isSync ?? true)
    }

    func testRegisterProbeLibraryLastModifiedCancellable() async throws {
        let expectation = XCTestExpectation(description: "Probe last modified succeeds")
        
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        let jsonResponse = """
        {
            "result": {
                "book_ids": [],
                "data": {
                    "last_modified": {
                        "1": {"v": "2026-06-23T18:00:00Z"}
                    }
                }
            }
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonResponse.data(using: .utf8)!)
        }
        
        var localLib = library!
        localLib.lastModified = Date(timeIntervalSince1970: 0)
        libraryManager.calibreLibraries[localLib.id] = localLib
        try libraryRepository.saveLibrary(localLib)
        
        let task = Task { @MainActor in
            for await update in container.calibreUpdates() {
                if case .library(let updatedLib) = update {
                    if updatedLib.id == localLib.id {
                        XCTAssertTrue(updatedLib.lastModified > Date(timeIntervalSince1970: 0))
                        expectation.fulfill()
                        return
                    }
                }
            }
        }
            
        await Task.yield()
        container.publishProbeLibraryLastModifiedRequest(.init(library: localLib, autoUpdateOnly: false, incremental: false))
        
        await fulfillment(of: [expectation], timeout: 5.0)
        task.cancel()
    }

    func testSyncLibraryAndSaveBookMetadata() async throws {
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let statusCode: Int
            let jsonString: String
            
            if path.contains("custom_columns") {
                statusCode = 200
                jsonString = "{}"
            } else if path.contains("categories") {
                statusCode = 200
                jsonString = "[]"
            } else if path.contains("list") {
                statusCode = 200
                jsonString = """
                {
                    "book_ids": [101],
                    "data": {
                        "last_modified": {
                            "101": {"v": "2026-06-23T18:00:00Z"}
                        }
                    }
                }
                """
            } else if path.contains("books") {
                statusCode = 200
                jsonString = "{}"
            } else {
                statusCode = 404
                jsonString = ""
            }
            
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8)!)
        }
        
        let syncReq = CalibreSyncLibraryRequest(library: library, autoUpdateOnly: false, incremental: false)
        await libraryManager.syncLibrary(request: syncReq)
        
        let syncStatus = libraryManager.librarySyncStatus[library.id]
        XCTAssertNotNil(syncStatus)
        XCTAssertFalse(syncStatus?.isSync ?? true)
        XCTAssertFalse(syncStatus?.isError ?? true)
        XCTAssertEqual(syncStatus?.msg, "Success")
    }

    func testPopulateLocalLibraryBooksWithFiles() throws {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            XCTFail("Failed to get document directory")
            return
        }
        let localLibraryURL = documentDirectoryURL.appendingPathComponent("Local Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: localLibraryURL, withIntermediateDirectories: true)
        
        let testBookFile = localLibraryURL.appendingPathComponent("TestBook.epub")
        try? "EPUB Content".write(to: testBookFile, atomically: true, encoding: .utf8)
        
        var completionCount = 0
        var completionWasOnMainThread = false
        libraryManager.populateLocalLibraryBooks {
            completionCount += 1
            completionWasOnMainThread = Thread.isMainThread
        }

        XCTAssertNotNil(libraryManager.localLibrary)
        XCTAssertEqual(libraryManager.localLibrary?.name, "Local Library")
        XCTAssertEqual(completionCount, 1)
        XCTAssertTrue(completionWasOnMainThread)

        try? FileManager.default.removeItem(at: testBookFile)
    }
}
