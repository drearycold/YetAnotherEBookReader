//
//  UnifiedSearchManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-10.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
class UnifiedSearchServiceTests: XCTestCase {
    
    var repository: MockSearchCacheRepository!
    var libraryProvider: MockLibraryProvider!
    var manager: UnifiedSearchService!
    var mockLibrary1: CalibreLibrary!
    var mockLibrary2: CalibreLibrary!
    var cancellables: Set<AnyCancellable>!
    var serverService: CalibreServerService!
    var container: AppContainer!
    
    override func setUp() async throws {
        try await super.setUp()

        let config = Realm.Configuration(inMemoryIdentifier: "UnifiedSearchServiceTests")
        DatabaseService.shared.setup(conf: config)
        container = MockAppContainerFactory.makeContainer(testName: "UnifiedSearchServiceTests")

        let server1 = CalibreServer(uuid: UUID(), name: "Server1", baseUrl: "http://localhost/1", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary1 = CalibreLibrary(server: server1, key: "lib1", name: "Library 1")
        
        let server2 = CalibreServer(uuid: UUID(), name: "Server2", baseUrl: "http://localhost/2", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary2 = CalibreLibrary(server: server2, key: "lib2", name: "Library 2")
        
        repository = MockSearchCacheRepository()
        libraryProvider = MockLibraryProvider()
        libraryProvider.libraries = [
            mockLibrary1.id: mockLibrary1,
            mockLibrary2.id: mockLibrary2
        ]
        
        serverService = container.calibreServerService
        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        manager = UnifiedSearchService(
            mergeService: UnifiedSearchMergeService(),
            repository: repository,
            librarySearchService: librarySearch,
            libraryProvider: libraryProvider
        )
        cancellables = Set<AnyCancellable>()
        
        await manager.setReachabilityProviders(
            reachable: { _, _ in true },
            reachableNoPublic: { _ in true }
        )
        
        // Setup ephemeral URLSession with MockURLProtocol
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        // Register mock sessions in the service
        for server in [server1, server2] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: 600, qos: qos)
                serverService.metadataSessions[key] = mockSession
            }
        }
        
        // Setup reachability staging in container
        let probeRequest1 = CalibreProbeServerRequest(server: server1, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info1 = CalibreServerInfo(server: server1, isPublic: false, url: URL(string: "http://localhost/1")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary1.id, libraryMap: [mockLibrary1.id: "Library 1"], request: probeRequest1)
        
        let probeRequest2 = CalibreProbeServerRequest(server: server2, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info2 = CalibreServerInfo(server: server2, isPublic: false, url: URL(string: "http://localhost/2")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary2.id, libraryMap: [mockLibrary2.id: "Library 2"], request: probeRequest2)
        
        container.calibreServerInfoStaging = [
            server1.uuid.uuidString: info1,
            server2.uuid.uuidString: info2
        ]
        
        // Default MockURLProtocol requestHandler
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let libraryId = url.path.components(separatedBy: "/").last ?? "lib1"
            let searchResultJSON = """
            {
                "total_num": 0,
                "sort_order": "asc",
                "num_books_without_search": 0,
                "offset": 0,
                "num": 0,
                "sort": "title",
                "base_url": "/ajax/search/\\(libraryId)",
                "query": "",
                "library_id": "\\(libraryId)",
                "book_ids": [],
                "vl": ""
            }
            """
            
            if url.path.contains("ajax/search") {
                return (response, searchResultJSON.data(using: .utf8)!)
            } else if url.path.contains("ajax/books") {
                return (response, "{}".data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }
    }
    
    override func tearDown() async throws {
        repository = nil
        libraryProvider = nil
        manager = nil
        mockLibrary1 = nil
        mockLibrary2 = nil
        cancellables = nil
        serverService = nil
        AppContainer.shared = nil
        try await super.tearDown()
    }
    
    func createMockBook(id: Int32, title: String, library: CalibreLibrary) -> CalibreBook {
        var book = CalibreBook(id: id, library: library)
        book.title = title
        book.timestamp = Date()
        book.pubDate = Date()
        book.lastModified = Date()
        book.lastSynced = book.lastModified
        return book
    }

    struct CapturedSearchRequest: Equatable {
        let offset: Int
        let num: Int
    }

    final class SearchRequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var requests = [CapturedSearchRequest]()

        func append(_ request: CapturedSearchRequest) {
            lock.lock()
            requests.append(request)
            lock.unlock()
        }

        func snapshot() -> [CapturedSearchRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }
    }

    final class MetadataRequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var requestedIds = [[Int32]]()

        func append(ids: [Int32]) {
            lock.lock()
            requestedIds.append(ids)
            lock.unlock()
        }

        func snapshot() -> [[Int32]] {
            lock.lock()
            defer { lock.unlock() }
            return requestedIds
        }
    }

    nonisolated static func makeSearchResultJSON(total: Int, offset: Int, num: Int, bookIds: [Int32], query: String = "test") -> String {
        """
        {
            "total_num": \(total),
            "sort_order": "asc",
            "num_books_without_search": \(total),
            "offset": \(offset),
            "num": \(num),
            "sort": "title",
            "base_url": "/ajax/search/lib1",
            "query": "\(query)",
            "library_id": "lib1",
            "book_ids": [\(bookIds.map(String.init).joined(separator: ","))],
            "vl": ""
        }
        """
    }

    nonisolated static func makeMetadataJSON(
        bookIds: [Int32],
        titles: [Int32: String] = [:],
        formats: [Int32: [String]] = [:]
    ) -> String {
        let entries = bookIds.map { id in
            let title = titles[id] ?? "Book \(id)"
            let bookFormats = formats[id] ?? ["epub"]
            let formatMetadata = bookFormats.map { format in
                """
                    "\(format)": { "path": "book-\(id).\(format)", "size": 100, "mtime": "2026-01-01T00:00:00+00:00" }
                """
            }.joined(separator: ",")
            let formatList = bookFormats.map { "\"\($0)\"" }.joined(separator: ",")
            let mainFormat = bookFormats.first ?? "epub"
            let otherFormats = bookFormats.dropFirst().map { format in
                "\"\(format)\": \"/get/\(format)/\(id)/lib1\""
            }.joined(separator: ",")
            return """
            "\(id)": {
                "thumbnail": "/get/thumb/\(id)/lib1",
                "series": null,
                "languages": ["eng"],
                "title_sort": "\(title)",
                "identifiers": {},
                "user_categories": {},
                "pages": 0,
                "authors": ["Author \(id)"],
                "link_maps": {},
                "cover": "/get/cover/\(id)/lib1",
                "author_sort": "Author \(id)",
                "title": "\(title)",
                "publisher": null,
                "author_sort_map": {"Author \(id)": "Author \(id)"},
                "tags": [],
                "user_metadata": {},
                "uuid": "uuid-\(id)",
                "last_modified": "2026-01-01T00:00:00+00:00",
                "series_index": null,
                "pubdate": "2026-01-01T00:00:00+00:00",
                "application_id": \(id),
                "rating": 0.0,
                "comments": "",
                "timestamp": "2026-01-01T00:00:00+00:00",
                "format_metadata": {
                    \(formatMetadata)
                },
                "formats": [\(formatList)],
                "main_format": {"\(mainFormat)": "/get/\(mainFormat)/\(id)/lib1"},
                "other_formats": {\(otherFormats)},
                "category_urls": {}
            }
            """
        }.joined(separator: ",")
        return "{\(entries)}"
    }

    private func collectResults(
        for key: SearchCriteriaMergedKey,
        timeout: TimeInterval = 5.0,
        until predicate: @escaping (UnifiedSearchResult) -> Bool
    ) async -> [UnifiedSearchResult] {
        let expectation = expectation(description: "Unified search stream emitted expected result")
        var results: [UnifiedSearchResult] = []
        var fulfilled = false
        let stream = await manager.search(key: key)
        let task = Task { @MainActor in
            for await update in stream {
                guard !Task.isCancelled else { break }
                let result = update.result
                results.append(result)
                if predicate(result), !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: timeout)
        task.cancel()
        return results
    }

    func waitUntil(
        timeout: TimeInterval = 2.0,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }

    func testLibrarySearchForceRefreshRebuildsFromFirstPage() async throws {
        let criteria = SearchCriteria(
            searchString: "force-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let cachedBooks = (1...100).map { createMockBook(id: Int32($0), title: "Cached \($0)", library: mockLibrary1) }
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 196,
                bookIds: (1...100).map(Int32.init),
                books: cachedBooks
            )
        )

        let searchRequests = SearchRequestRecorder()
        let firstPageIds = (1...100).map(Int32.init)
        let metadataJSON = Self.makeMetadataJSON(bookIds: firstPageIds)

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                searchRequests.append(CapturedSearchRequest(offset: offset, num: num))

                let json = Self.makeSearchResultJSON(total: 198, offset: offset, num: num, bookIds: firstPageIds, query: "force-refresh")
                return (response, json.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 100,
            force: true
        )

        let capturedRequests = searchRequests.snapshot()

        XCTAssertEqual(capturedRequests, [CapturedSearchRequest(offset: 0, num: 100)])
        let source = try XCTUnwrap(result.sources["http://localhost/1"])
        XCTAssertEqual(source.totalNumber, 198)
        XCTAssertEqual(source.bookIds, firstPageIds)
    }

    func testLibrarySearchRebuildsWhenIncrementalPageOverlapsAfterServerInsert() async throws {
        let criteria = SearchCriteria(
            searchString: "overlap-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let cachedIds = (1...100).map(Int32.init)
        let cachedBooks = cachedIds.map { createMockBook(id: $0, title: "Cached \($0)", library: mockLibrary1) }
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 196,
                bookIds: cachedIds,
                books: cachedBooks
            )
        )

        let overlappingPageIds = (99...196).map(Int32.init)
        let rebuiltIds = [Int32(201), Int32(202)] + (1...196).map(Int32.init)
        let metadataJSON = Self.makeMetadataJSON(bookIds: rebuiltIds)
        let searchRequests = SearchRequestRecorder()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                searchRequests.append(CapturedSearchRequest(offset: offset, num: num))

                if offset == 100 {
                    let json = Self.makeSearchResultJSON(total: 198, offset: offset, num: num, bookIds: overlappingPageIds, query: "overlap-refresh")
                    return (response, json.data(using: .utf8)!)
                }
                if offset == 0 {
                    let json = Self.makeSearchResultJSON(total: 198, offset: offset, num: num, bookIds: rebuiltIds, query: "overlap-refresh")
                    return (response, json.data(using: .utf8)!)
                }
                throw URLError(.badServerResponse)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 198,
            force: false
        )

        let capturedRequests = searchRequests.snapshot()

        XCTAssertEqual(capturedRequests, [
            CapturedSearchRequest(offset: 100, num: 98),
            CapturedSearchRequest(offset: 0, num: 198)
        ])

        let source = try XCTUnwrap(result.sources["http://localhost/1"])
        XCTAssertEqual(source.totalNumber, 198)
        XCTAssertEqual(source.bookIds.count, 198)
        XCTAssertEqual(Set(source.bookIds).count, 198)
        XCTAssertTrue(source.bookIds.contains(201))
        XCTAssertTrue(source.bookIds.contains(202))
        XCTAssertEqual(source.books.count, 198)
    }

    func testLibrarySearchRebuildsWhenIncrementalTotalDropsAfterServerDelete() async throws {
        let criteria = SearchCriteria(
            searchString: "delete-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let cachedIds = (1...100).map(Int32.init)
        let cachedBooks = cachedIds.map { createMockBook(id: $0, title: "Cached \($0)", library: mockLibrary1) }
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 198,
                bookIds: cachedIds,
                books: cachedBooks
            )
        )

        let deletedTailPageIds = (101...196).map(Int32.init)
        let rebuiltIds = (1...196).map(Int32.init)
        let metadataJSON = Self.makeMetadataJSON(bookIds: rebuiltIds)
        let searchRequests = SearchRequestRecorder()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                searchRequests.append(CapturedSearchRequest(offset: offset, num: num))

                if offset == 100 {
                    let json = Self.makeSearchResultJSON(total: 196, offset: offset, num: num, bookIds: deletedTailPageIds, query: "delete-refresh")
                    return (response, json.data(using: .utf8)!)
                }
                if offset == 0 {
                    let json = Self.makeSearchResultJSON(total: 196, offset: offset, num: num, bookIds: rebuiltIds, query: "delete-refresh")
                    return (response, json.data(using: .utf8)!)
                }
                throw URLError(.badServerResponse)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 198,
            force: false
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])

        XCTAssertEqual(searchRequests.snapshot(), [
            CapturedSearchRequest(offset: 100, num: 98),
            CapturedSearchRequest(offset: 0, num: 198)
        ])
        XCTAssertEqual(source.totalNumber, 196)
        XCTAssertEqual(source.bookIds, rebuiltIds)
        XCTAssertEqual(source.books.count, 196)
        XCTAssertFalse(source.bookIds.contains(197))
        XCTAssertFalse(source.bookIds.contains(198))
    }

    func testLibrarySearchRebuildsWhenIncrementalPageOverlapsAfterServerReorderWithSameTotal() async throws {
        let criteria = SearchCriteria(
            searchString: "reorder-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let cachedIds = (1...100).map(Int32.init)
        let cachedBooks = cachedIds.map { createMockBook(id: $0, title: "Cached \($0)", library: mockLibrary1) }
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 196,
                bookIds: cachedIds,
                books: cachedBooks
            )
        )

        let overlappingTailPageIds = (100...195).map(Int32.init)
        let rebuiltIds = [Int32(150)] + (1...149).map(Int32.init) + (151...196).map(Int32.init)
        let metadataJSON = Self.makeMetadataJSON(bookIds: rebuiltIds)
        let searchRequests = SearchRequestRecorder()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                searchRequests.append(CapturedSearchRequest(offset: offset, num: num))

                if offset == 100 {
                    let json = Self.makeSearchResultJSON(total: 196, offset: offset, num: num, bookIds: overlappingTailPageIds, query: "reorder-refresh")
                    return (response, json.data(using: .utf8)!)
                }
                if offset == 0 {
                    let json = Self.makeSearchResultJSON(total: 196, offset: offset, num: num, bookIds: rebuiltIds, query: "reorder-refresh")
                    return (response, json.data(using: .utf8)!)
                }
                throw URLError(.badServerResponse)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 196,
            force: false
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])

        XCTAssertEqual(searchRequests.snapshot(), [
            CapturedSearchRequest(offset: 100, num: 96),
            CapturedSearchRequest(offset: 0, num: 196)
        ])
        XCTAssertEqual(source.totalNumber, 196)
        XCTAssertEqual(source.bookIds.count, 196)
        XCTAssertEqual(Set(source.bookIds).count, 196)
        XCTAssertEqual(source.bookIds.first, 150)
        XCTAssertEqual(source.bookIds, rebuiltIds)
    }

    func testLibrarySearchRebuildsStaleGenerationAfterServerMetadataChange() async throws {
        var updatedLibrary = mockLibrary1!
        updatedLibrary.lastModified = Date(timeIntervalSince1970: 100)

        let criteria = SearchCriteria(
            searchString: "metadata-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let cachedIds = (1...100).map(Int32.init)
        let cachedBooks = cachedIds.map { createMockBook(id: $0, title: "Cached \($0)", library: updatedLibrary) }
        try repository.saveLibrarySourceResult(
            libraryId: updatedLibrary.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: Date(timeIntervalSince1970: 0),
                totalNumber: 100,
                bookIds: cachedIds,
                books: cachedBooks
            )
        )

        let rebuiltIds = [Int32(50)] + (1...49).map(Int32.init) + (51...100).map(Int32.init)
        let metadataJSON = Self.makeMetadataJSON(bookIds: rebuiltIds, titles: [50: "AAA Updated Title"])
        let searchRequests = SearchRequestRecorder()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                searchRequests.append(CapturedSearchRequest(offset: offset, num: num))

                let json = Self.makeSearchResultJSON(total: 100, offset: offset, num: num, bookIds: rebuiltIds, query: "metadata-refresh")
                return (response, json.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: updatedLibrary,
            criteria: criteria,
            limit: 100,
            force: false
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])

        XCTAssertEqual(searchRequests.snapshot(), [CapturedSearchRequest(offset: 0, num: 100)])
        XCTAssertEqual(source.generation, updatedLibrary.lastModified)
        XCTAssertEqual(source.bookIds, rebuiltIds)
        XCTAssertEqual(source.books.first?.id, 50)
        XCTAssertEqual(source.books.first?.title, "AAA Updated Title")
    }

    func testLibrarySearchRefreshesResetSentinelBooksBeforeReturningCachedResult() async throws {
        let criteria = SearchCriteria(
            searchString: "reset-sentinel-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        var resetBook = CalibreBook(id: 301, library: mockLibrary1)
        resetBook.title = CalibreBook.resetMetadataTitle
        resetBook.lastModified = Date(timeIntervalSince1970: 0)
        resetBook.lastSynced = Date(timeIntervalSince1970: 0)

        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 1,
                bookIds: [301],
                books: [resetBook]
            )
        )

        let metadataRequests = MetadataRequestRecorder()
        let metadataJSON = Self.makeMetadataJSON(bookIds: [301], titles: [301: "Restored Server Title"])

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/books/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let ids = components?.queryItems?.first(where: { $0.name == "ids" })?.value?
                    .split(separator: ",")
                    .compactMap { Int32(String($0)) } ?? []
                metadataRequests.append(ids: ids)
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 100,
            force: false
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])

        XCTAssertEqual(metadataRequests.snapshot(), [[301]])
        XCTAssertEqual(source.books.map(\.title), ["Restored Server Title"])
        XCTAssertFalse(source.books.contains { $0.title == CalibreBook.resetMetadataTitle })
    }

    func testLibrarySearchRefreshesExistingStaleBooksDuringSearchFetch() async throws {
        let criteria = SearchCriteria(
            searchString: "stale-existing-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        var staleBook = createMockBook(id: 401, title: "Old Cached Title", library: mockLibrary1)
        staleBook.lastModified = Date(timeIntervalSince1970: 200)
        staleBook.lastSynced = Date(timeIntervalSince1970: 100)
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 1,
                bookIds: [401],
                books: [staleBook]
            )
        )

        let metadataRequests = MetadataRequestRecorder()
        let metadataJSON = Self.makeMetadataJSON(bookIds: [401], titles: [401: "Fresh Server Title"])

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                let json = Self.makeSearchResultJSON(total: 1, offset: offset, num: num, bookIds: [401], query: "stale-existing-refresh")
                return (response, json.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let ids = components?.queryItems?.first(where: { $0.name == "ids" })?.value?
                    .split(separator: ",")
                    .compactMap { Int32(String($0)) } ?? []
                metadataRequests.append(ids: ids)
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 100,
            force: true
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])

        XCTAssertEqual(metadataRequests.snapshot(), [[401]])
        XCTAssertEqual(source.books.map(\.title), ["Fresh Server Title"])
    }

    func testLibrarySearchDoesNotRefreshFreshExistingBooksDuringNormalSearchFetch() async throws {
        let criteria = SearchCriteria(
            searchString: "fresh-existing-no-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let freshBook = createMockBook(id: 501, title: "Fresh Cached Title", library: mockLibrary1)
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 1,
                bookIds: [501],
                books: [freshBook]
            )
        )

        let metadataRequests = MetadataRequestRecorder()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                let json = Self.makeSearchResultJSON(total: 1, offset: offset, num: num, bookIds: [501], query: "fresh-existing-no-refresh")
                return (response, json.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let ids = components?.queryItems?.first(where: { $0.name == "ids" })?.value?
                    .split(separator: ",")
                    .compactMap { Int32(String($0)) } ?? []
                metadataRequests.append(ids: ids)
                return (response, "{}".data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 100,
            force: false
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])

        XCTAssertEqual(metadataRequests.snapshot(), [])
        XCTAssertEqual(source.books.map(\.title), ["Fresh Cached Title"])
    }

    func testLibrarySearchForceMetadataRefreshUpdatesFreshExistingFormats() async throws {
        let criteria = SearchCriteria(
            searchString: "fresh-existing-force-format-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        var freshBook = createMockBook(id: 601, title: "Fresh Cached Title", library: mockLibrary1)
        freshBook.formats = [
            "EPUB": FormatInfo(serverSize: 100, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date())
        ]
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 1,
                bookIds: [601],
                books: [freshBook]
            )
        )

        let metadataRequests = MetadataRequestRecorder()
        let metadataJSON = Self.makeMetadataJSON(
            bookIds: [601],
            titles: [601: "Fresh Cached Title"],
            formats: [601: ["epub", "pdf"]]
        )

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                let json = Self.makeSearchResultJSON(total: 1, offset: offset, num: num, bookIds: [601], query: "fresh-existing-force-format-refresh")
                return (response, json.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let ids = components?.queryItems?.first(where: { $0.name == "ids" })?.value?
                    .split(separator: ",")
                    .compactMap { Int32(String($0)) } ?? []
                metadataRequests.append(ids: ids)
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 100,
            force: true,
            forceMetadataRefresh: true
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])
        let refreshedBook = try XCTUnwrap(source.books.first)

        XCTAssertEqual(metadataRequests.snapshot(), [[601]])
        XCTAssertNotNil(refreshedBook.formats["EPUB"])
        XCTAssertNotNil(refreshedBook.formats["PDF"])
    }

    func testManualRefreshKeepsMetadataRefreshEnabledForLoadedMoreBooks() async throws {
        let criteria = SearchCriteria(
            searchString: "manual-refresh-load-more-formats",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        let firstPageIds = (1...100).map(Int32.init)
        let secondPageIds = (101...200).map(Int32.init)
        let cachedBooks = firstPageIds.map { id -> CalibreBook in
            var book = createMockBook(id: id, title: "Cached \(id)", library: mockLibrary1)
            book.formats = [
                "EPUB": FormatInfo(serverSize: 100, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date())
            ]
            return book
        }
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: criteria.searchString,
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: LibrarySourceSearchResult(
                generation: mockLibrary1.lastModified,
                totalNumber: 200,
                bookIds: firstPageIds,
                books: cachedBooks
            )
        )

        let metadataRequests = MetadataRequestRecorder()
        let allIds = firstPageIds + secondPageIds
        let formats = allIds.reduce(into: [Int32: [String]]()) { partialResult, id in
            partialResult[id] = ["epub", "pdf"]
        }
        let metadataJSON = Self.makeMetadataJSON(bookIds: allIds, formats: formats)

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                let ids = offset == 0 ? firstPageIds : secondPageIds
                let json = Self.makeSearchResultJSON(total: 200, offset: offset, num: num, bookIds: ids, query: "manual-refresh-load-more-formats")
                return (response, json.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let ids = components?.queryItems?.first(where: { $0.name == "ids" })?.value?
                    .split(separator: ",")
                    .compactMap { Int32(String($0)) } ?? []
                metadataRequests.append(ids: ids)
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let stream = await manager.search(key: key)
        let streamTask = Task {
            for await _ in stream {
                guard !Task.isCancelled else { break }
            }
        }
        defer {
            streamTask.cancel()
        }

        let initialLoaded = await waitUntil {
            await self.manager.getActiveSearch(for: key)?.books.count == 100
        }
        XCTAssertTrue(initialLoaded)

        await manager.resetSearchAndWait(for: key, force: true)
        let refreshedFirstPage = await waitUntil {
            guard let result = await self.manager.getActiveSearch(for: key) else { return false }
            return result.books.count == 100 && result.books.allSatisfy { $0.formats["PDF"] != nil }
        }
        XCTAssertTrue(refreshedFirstPage)

        await manager.expandLimit(for: key, by: 100)
        let expandedAndRefreshed = await waitUntil {
            guard let result = await self.manager.getActiveSearch(for: key) else { return false }
            return result.books.count == 200 && result.books.suffix(100).allSatisfy { $0.formats["PDF"] != nil }
        }
        XCTAssertTrue(expandedAndRefreshed)

        XCTAssertEqual(metadataRequests.snapshot(), [firstPageIds, secondPageIds])
    }

    func testLibrarySearchDeduplicatesDuplicateServerIdsDuringRebuild() async throws {
        let criteria = SearchCriteria(
            searchString: "duplicate-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let serverIdsWithDuplicates: [Int32] = [1, 2, 2, 3, 1, 4]
        let expectedIds: [Int32] = [1, 2, 3, 4]
        let metadataJSON = Self.makeMetadataJSON(bookIds: expectedIds)
        let searchRequests = SearchRequestRecorder()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? -1
                let num = Int(components?.queryItems?.first(where: { $0.name == "num" })?.value ?? "") ?? -1
                searchRequests.append(CapturedSearchRequest(offset: offset, num: num))

                let json = Self.makeSearchResultJSON(total: 4, offset: offset, num: num, bookIds: serverIdsWithDuplicates, query: "duplicate-refresh")
                return (response, json.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(
            library: mockLibrary1,
            criteria: criteria,
            limit: 100,
            force: true
        )

        let source = try XCTUnwrap(result.sources["http://localhost/1"])

        XCTAssertEqual(searchRequests.snapshot(), [CapturedSearchRequest(offset: 0, num: 100)])
        XCTAssertEqual(source.totalNumber, 4)
        XCTAssertEqual(source.bookIds, expectedIds)
        XCTAssertEqual(source.books.map(\.id), expectedIds)
    }
    
    func testAsyncStreamAndIncrementalMerging() async throws {
        // Setup ephemeral URLSession with MockURLProtocol
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        for server in [mockLibrary1.server, mockLibrary2.server] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: 600, qos: qos)
                serverService.metadataSessions[key] = mockSession
            }
        }
        
        let searchResultJSON1 = """
        {
            "total_num": 1,
            "sort_order": "asc",
            "num_books_without_search": 1,
            "offset": 0,
            "num": 1,
            "sort": "title",
            "base_url": "/ajax/search/lib1",
            "query": "test",
            "library_id": "lib1",
            "book_ids": [1],
            "vl": ""
        }
        """
        
        let metadataJSON1 = """
        {
            "1": {
                "thumbnail": "/get/thumb/1/lib1",
                "series": null,
                "languages": ["eng"],
                "title_sort": "Apple",
                "identifiers": {},
                "user_categories": {},
                "pages": 0,
                "authors": ["Author A"],
                "link_maps": {},
                "cover": "/get/cover/1/lib1",
                "author_sort": "A, Author",
                "title": "Apple",
                "publisher": null,
                "author_sort_map": {"Author A": "A, Author"},
                "tags": [],
                "user_metadata": {},
                "uuid": "uuid-apple",
                "last_modified": "2023-07-25T03:11:04+00:00",
                "series_index": null,
                "pubdate": "2023-07-21T07:43:05+00:00",
                "application_id": 1,
                "rating": 0.0,
                "comments": "",
                "timestamp": "2023-07-21T07:43:05+00:00",
                "format_metadata": {
                    "epub": { "path": "apple.epub", "size": 100, "mtime": "2023-07-21T07:43:05+00:00" }
                },
                "formats": ["epub"],
                "main_format": {"epub": "/get/epub/1/lib1"},
                "other_formats": {},
                "category_urls": {}
            }
        }
        """
        
        let searchResultJSON2 = """
        {
            "total_num": 1,
            "sort_order": "asc",
            "num_books_without_search": 1,
            "offset": 0,
            "num": 1,
            "sort": "title",
            "base_url": "/ajax/search/lib2",
            "query": "test",
            "library_id": "lib2",
            "book_ids": [2],
            "vl": ""
        }
        """
        
        let metadataJSON2 = """
        {
            "2": {
                "thumbnail": "/get/thumb/2/lib2",
                "series": null,
                "languages": ["eng"],
                "title_sort": "Banana",
                "identifiers": {},
                "user_categories": {},
                "pages": 0,
                "authors": ["Author B"],
                "link_maps": {},
                "cover": "/get/cover/2/lib2",
                "author_sort": "B, Author",
                "title": "Banana",
                "publisher": null,
                "author_sort_map": {"Author B": "B, Author"},
                "tags": [],
                "user_metadata": {},
                "uuid": "uuid-banana",
                "last_modified": "2023-07-25T03:11:04+00:00",
                "series_index": null,
                "pubdate": "2023-07-21T07:43:05+00:00",
                "application_id": 2,
                "rating": 0.0,
                "comments": "",
                "timestamp": "2023-07-21T07:43:05+00:00",
                "format_metadata": {
                    "epub": { "path": "banana.epub", "size": 200, "mtime": "2023-07-21T07:43:05+00:00" }
                },
                "formats": ["epub"],
                "main_format": {"epub": "/get/epub/2/lib2"},
                "other_formats": {},
                "category_urls": {}
            }
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            if url.path.contains("ajax/search/lib1") {
                return (response, searchResultJSON1.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON1.data(using: .utf8)!)
            } else if url.path.contains("ajax/search/lib2") {
                return (response, searchResultJSON2.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib2") {
                return (response, metadataJSON2.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }
        
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id, mockLibrary2.id], criteria: criteria)
        
        let receivedResults = await collectResults(for: key) { result in
            result.books.count == 2
        }
        
        XCTAssertGreaterThanOrEqual(receivedResults.count, 2)
        let finalResult = receivedResults.last!
        XCTAssertEqual(finalResult.books.count, 2)
        XCTAssertEqual(finalResult.books.getOrNil(0)?.title, "Apple")
        XCTAssertEqual(finalResult.books.getOrNil(1)?.title, "Banana")
    }

    func testResetSearchAndWaitReturnsAfterForcedNetworkRequestCompletes() async throws {
        let criteria = SearchCriteria(
            searchString: "awaitable-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        let requestLock = NSLock()
        var completedRequestCount = 0

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            Thread.sleep(forTimeInterval: 0.05)

            requestLock.lock()
            completedRequestCount += 1
            requestLock.unlock()

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let searchResultJSON = """
            {
                "total_num": 0,
                "sort_order": "asc",
                "num_books_without_search": 0,
                "offset": 0,
                "num": 0,
                "sort": "title",
                "base_url": "/ajax/search/lib1",
                "query": "",
                "library_id": "lib1",
                "book_ids": [],
                "vl": ""
            }
            """
            return (response, searchResultJSON.data(using: .utf8)!)
        }

        let stream = await manager.search(key: key)
        for await update in stream {
            if update.statuses[mockLibrary1.id]?.loading == false {
                break
            }
        }

        requestLock.lock()
        let requestsBeforeRefresh = completedRequestCount
        requestLock.unlock()

        await manager.resetSearchAndWait(for: key, force: true)

        requestLock.lock()
        let requestsAfterRefresh = completedRequestCount
        requestLock.unlock()
        XCTAssertGreaterThan(requestsAfterRefresh, requestsBeforeRefresh)
    }
    
    func testExpandLimitAndResetSearch() async throws {
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
        // Prep cache
        let book1 = createMockBook(id: 1, title: "A", library: mockLibrary1)
        let book2 = createMockBook(id: 2, title: "B", library: mockLibrary1)
        let lib1Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 2,
            bookIds: [1, 2],
            books: [book1, book2]
        )
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: lib1Result
        )
        
        let initialResults = await collectResults(for: key) { result in
            result.books.count == 2
        }
        let lastResult = initialResults.last
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        await manager.expandLimit(for: key, by: 50)
        let expandedResults = await collectResults(for: key) { result in
            result.limitNumber == 150
        }
        let lastExpandedResult = expandedResults.last
        XCTAssertEqual(lastExpandedResult?.limitNumber, 150)
        
        // Reset search
        await manager.resetSearch(for: key)
        let resetResults = await collectResults(for: key) { result in
            result.limitNumber == 100
        }
        let lastResetResult = resetResults.last
        XCTAssertEqual(lastResetResult?.limitNumber, 100)
    }
    
    func testEmptyLibraryIdsMergingAndExpansion() async throws {
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        // Key with empty libraryIds representing "All Libraries"
        let key = SearchCriteriaMergedKey(libraryIds: [], criteria: criteria)
        
        // Save mock library cached results
        let book1 = createMockBook(id: 1, title: "A", library: mockLibrary1)
        let book2 = createMockBook(id: 2, title: "B", library: mockLibrary2)
        
        let lib1Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 1,
            bookIds: [1],
            books: [book1]
        )
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: lib1Result
        )
        
        let lib2Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 1,
            bookIds: [2],
            books: [book2]
        )
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary2.id,
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/2",
            result: lib2Result
        )
        
        let initialResults = await collectResults(for: key) { result in
            result.books.count == 2
        }
        let lastResult = initialResults.last
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.totalNumber, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        await manager.expandLimit(for: key, by: 50)
        let expandedResults = await collectResults(for: key) { result in
            result.limitNumber == 150
        }
        let lastExpandedResult = expandedResults.last
        XCTAssertEqual(lastExpandedResult?.limitNumber, 150)
    }
    
    func testMultipleSearchCriteriaHandling() async throws {
        let criteriaA = SearchCriteria(
            searchString: "apple",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let criteriaB = SearchCriteria(
            searchString: "banana",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        
        let keyA = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaA)
        let keyB = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaB)
        
        // Prep cache for A
        let bookA = createMockBook(id: 1, title: "Apple", library: mockLibrary1)
        let resA = LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [1], books: [bookA])
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: "apple",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: resA
        )
        
        // Prep cache for B
        let bookB = createMockBook(id: 2, title: "Banana", library: mockLibrary1)
        let resB = LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [2], books: [bookB])
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: "banana",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: resB
        )
        
        async let resultsA = collectResults(for: keyA) { result in
            result.books.count == 1
        }
        async let resultsB = collectResults(for: keyB) { result in
            result.books.count == 1
        }
        let finalResultsA = await resultsA
        let finalResultsB = await resultsB
        
        XCTAssertEqual(finalResultsA.last?.books.first?.title, "Apple")
        XCTAssertEqual(finalResultsB.last?.books.first?.title, "Banana")
    }
    
    func testLimitExpansionIsolatesCriteria() async throws {
        let criteriaA = SearchCriteria(
            searchString: "apple",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let criteriaB = SearchCriteria(
            searchString: "banana",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        
        let keyA = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaA)
        let keyB = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaB)
        
        async let resultsA = collectResults(for: keyA) { _ in true }
        async let resultsB = collectResults(for: keyB) { _ in true }
        let initialResultsA = await resultsA
        let initialResultsB = await resultsB
        
        XCTAssertEqual(initialResultsA.last?.limitNumber, 100)
        XCTAssertEqual(initialResultsB.last?.limitNumber, 100)
        
        // Expand limit for A only
        await manager.expandLimit(for: keyA, by: 50)
        let expandedA = await collectResults(for: keyA) { result in
            result.limitNumber == 150
        }
        XCTAssertEqual(expandedA.last?.limitNumber, 150)
        
        // Verify B's limit is still 100
        let currentB = await manager.getActiveSearch(for: keyB)
        XCTAssertEqual(currentB?.limitNumber, 100)
    }

    func testSearchCancellation() async throws {
        let criteria = SearchCriteria(
            searchString: "cancellation-test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
        MockURLProtocol.requestHandler = { request in
            Thread.sleep(forTimeInterval: 1.0)
            throw URLError(.cancelled)
        }
        
        let exp = expectation(description: "Subscription yields initial status")
        var receivedUpdate: SearchUpdate?
        
        var fulfilledCancellation = false
        let stream = await manager.search(key: key)
        let task = Task {
            for await update in stream {
                receivedUpdate = update
                if !fulfilledCancellation {
                    fulfilledCancellation = true
                    exp.fulfill()
                }
            }
        }
        
        await fulfillment(of: [exp], timeout: 2.0)
        task.cancel()
        
        XCTAssertNotNil(receivedUpdate)
    }

    func testSearchTimeout() async throws {
        let criteria = SearchCriteria(
            searchString: "timeout-test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
        MockURLProtocol.requestHandler = { request in
            throw URLError(.timedOut)
        }
        
        let exp = expectation(description: "Results received with error")
        var lastUpdate: SearchUpdate?
        
        var fulfilledTimeout = false
        let stream = await manager.search(key: key)
        let task = Task {
            for await update in stream {
                lastUpdate = update
                if let status = update.statuses[mockLibrary1.id], !status.loading && status.error != nil {
                    if !fulfilledTimeout {
                        fulfilledTimeout = true
                        exp.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [exp], timeout: 2.0)
        task.cancel()
        
        XCTAssertNotNil(lastUpdate)
        let status = lastUpdate?.statuses[mockLibrary1.id]
        XCTAssertEqual(status?.loading, false)
        XCTAssertNotNil(status?.error)
    }

    func testSearchEmptyResults() async throws {
        let criteria = SearchCriteria(
            searchString: "empty-test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let searchResultJSON = """
            {
                "total_num": 0,
                "sort_order": "asc",
                "num_books_without_search": 0,
                "offset": 0,
                "num": 0,
                "sort": "title",
                "base_url": "/ajax/search/lib1",
                "query": "empty-test",
                "library_id": "lib1",
                "book_ids": [],
                "vl": ""
            }
            """
            return (response, searchResultJSON.data(using: .utf8)!)
        }
        
        let exp = expectation(description: "Empty results received")
        var finalResult: UnifiedSearchResult?
        
        var fulfilledEmpty = false
        let stream = await manager.search(key: key)
        let task = Task {
            for await update in stream {
                if let status = update.statuses[mockLibrary1.id], !status.loading {
                    if !fulfilledEmpty {
                        fulfilledEmpty = true
                        finalResult = update.result
                        exp.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [exp], timeout: 2.0)
        task.cancel()
        
        XCTAssertNotNil(finalResult)
        XCTAssertEqual(finalResult?.books.count, 0)
    }

    // MARK: - Metadata in batches

    /// Answers `ajax/search` with `bookIds`, and `ajax/books` with each requested book, recording
    /// the ids of each request; `failing` gets HTTP 400 for a request that asks for it.
    private func answerSearch(bookIds: [Int32], query: String, recorder: MetadataRequestRecorder, failing: Int32? = nil) {
        let searchJSON = Self.makeSearchResultJSON(total: bookIds.count, offset: 0, num: bookIds.count, bookIds: bookIds, query: query)
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            if url.path.contains("ajax/search/lib1") {
                return (ok, searchJSON.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                let ids = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "ids" })?.value?
                    .split(separator: ",")
                    .compactMap { Int32(String($0)) } ?? []
                recorder.append(ids: ids)
                if let failing, ids.contains(failing) {
                    return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
                }
                return (ok, Self.makeMetadataJSON(bookIds: ids).data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }
    }

    /// Browsing reads books' metadata in batches: calibre refuses a request line over 8 KB, which
    /// about 1,300 ids reach.
    func testLibrarySearchReadsMetadataInBatches() async throws {
        let criteria = SearchCriteria(searchString: "batches", sortCriteria: LibrarySearchSort(by: .Title, ascending: true), filterCriteriaCategory: [:])
        let recorder = MetadataRequestRecorder()
        answerSearch(bookIds: (1...450).map(Int32.init), query: criteria.searchString, recorder: recorder)

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(library: mockLibrary1, criteria: criteria, limit: 450, force: true)

        XCTAssertEqual(recorder.snapshot().map(\.count), [200, 200, 50])
        XCTAssertEqual(try XCTUnwrap(result.sources["http://localhost/1"]).books.count, 450)
    }

    /// A batch that doesn't arrive leaves the cache's generation as it was, so the next search reads
    /// the books again rather than taking them for up to date.
    func testAFailedMetadataBatchLeavesTheBooksToBeReadAgain() async throws {
        let criteria = SearchCriteria(searchString: "failed-batch", sortCriteria: LibrarySearchSort(by: .Title, ascending: true), filterCriteriaCategory: [:])
        var library: CalibreLibrary = mockLibrary1
        library.lastModified = Date(timeIntervalSince1970: 1_000)
        let recorder = MetadataRequestRecorder()
        answerSearch(bookIds: (1...250).map(Int32.init), query: criteria.searchString, recorder: recorder, failing: 201)

        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        let result = try await librarySearch.searchAndFetchMetadata(library: library, criteria: criteria, limit: 250, force: true)

        XCTAssertEqual(recorder.snapshot().map(\.count), [200, 50])
        let source = try XCTUnwrap(result.sources["http://localhost/1"])
        XCTAssertEqual(source.books.count, 200)
        XCTAssertLessThan(source.generation, library.lastModified)
    }

    // MARK: - Failures and the search cache

    private var offlineCriteria: SearchCriteria {
        SearchCriteria(
            searchString: "offline",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
    }

    private func cacheBooks(_ ids: [Int32], total: Int, of library: CalibreLibrary, source: String) throws {
        try repository.saveLibrarySourceResult(
            libraryId: library.id,
            search: offlineCriteria.searchString,
            sortBy: offlineCriteria.sortCriteria.by,
            sortAsc: offlineCriteria.sortCriteria.ascending,
            filters: offlineCriteria.filterCriteriaCategory,
            sourceUrl: source,
            result: LibrarySourceSearchResult(
                generation: library.lastModified,
                totalNumber: total,
                bookIds: ids,
                books: ids.map { createMockBook(id: $0, title: "Cached \($0)", library: library) }
            )
        )
    }

    private func collectUpdates(
        for key: SearchCriteriaMergedKey,
        timeout: TimeInterval = 5.0,
        until predicate: @escaping (SearchUpdate) -> Bool
    ) async -> [SearchUpdate] {
        let expectation = expectation(description: "Unified search stream emitted expected update")
        var updates: [SearchUpdate] = []
        var fulfilled = false
        let stream = await manager.search(key: key)
        let task = Task { @MainActor in
            for await update in stream {
                guard !Task.isCancelled else { break }
                updates.append(update)
                if predicate(update), !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: timeout)
        task.cancel()
        return updates
    }

    /// A library whose search fails shows what its search cache had and says why. It has no more
    /// to give, so the books it had don't hold back another library's that sort after them.
    func testAFailedLibraryShowsItsCacheWithoutHoldingBackTheOthers() async throws {
        try cacheBooks([1, 2], total: 5, of: mockLibrary1, source: "http://localhost/1")
        let searchJSON = Self.makeSearchResultJSON(total: 1, offset: 0, num: 1, bookIds: [7], query: "offline")
        let metadataJSON = Self.makeMetadataJSON(bookIds: [7], titles: [7: "Zebra"])
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path.contains("/lib1") {
                throw URLError(.cannotConnectToHost)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            if url.path.contains("ajax/search/lib2") {
                return (response, searchJSON.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib2") {
                return (response, metadataJSON.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id, mockLibrary2.id], criteria: offlineCriteria)

        let updates = await collectUpdates(for: key) { update in
            update.statuses.values.allSatisfy { !$0.loading }
        }

        let last = try XCTUnwrap(updates.last)
        let status = try XCTUnwrap(last.statuses[mockLibrary1.id])
        XCTAssertNotNil(status.failure)
        XCTAssertTrue(status.fromCache)
        XCTAssertNil(last.statuses[mockLibrary2.id]?.error)
        XCTAssertEqual(last.result.books.map(\.title), ["Cached 1", "Cached 2", "Zebra"])
        XCTAssertEqual(last.result.totalNumber, 3)
    }

    /// A library whose search fails with nothing cached isn't left loading: Browse says why. This
    /// searches all libraries, as Browse does, where the merge has no offsets for such a library.
    func testAFailedLibraryWithoutACacheSaysWhyInsteadOfLoading() async throws {
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        libraryProvider.libraries = [mockLibrary1.id: mockLibrary1]
        container.libraryManager.calibreLibraries = [mockLibrary1.id: mockLibrary1]
        let key = SearchCriteriaMergedKey(libraryIds: [], criteria: offlineCriteria)

        let libraryId = mockLibrary1.id
        let updates = await collectUpdates(for: key) { update in
            update.statuses[libraryId]?.failure != nil
        }

        let last = try XCTUnwrap(updates.last)
        XCTAssertEqual(last.statuses[mockLibrary1.id]?.fromCache, false)
        XCTAssertTrue(last.result.books.isEmpty)
        let viewModel = LibraryInfoView.ViewModel()
        XCTAssertEqual(viewModel.getLibraryLoadingCount(container: container, searchResult: last.result, libraryStatuses: last.statuses), 0)
        XCTAssertEqual(viewModel.getLibrarySearchingText(container: container, searchResult: last.result, libraryStatuses: last.statuses), "Couldn't search 1 library")
        let failureText = try XCTUnwrap(viewModel.getLibrarySearchFailureText(container: container, searchResult: last.result, libraryStatuses: last.statuses))
        XCTAssertTrue(failureText.hasPrefix("Couldn't search Library 1: "), failureText)
    }

    /// A server that can't be reached is looked up by its base URL. Books read through its public
    /// URL are still shown.
    func testAnUnreachableServerShowsWhatWasReadThroughItsOtherURL() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Server3", baseUrl: "http://localhost/3", hasPublicUrl: true, publicUrl: "http://public.example/3", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib3", name: "Library 3")
        libraryProvider.libraries[library.id] = library
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
            serverService.metadataSessions[CalibreServerURLSessionKey(server: server, timeout: 600, qos: qos)] = mockSession
        }
        try cacheBooks([4], total: 1, of: library, source: "http://public_example/3")
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        let key = SearchCriteriaMergedKey(libraryIds: [library.id], criteria: offlineCriteria)

        let updates = await collectUpdates(for: key) { update in
            update.statuses[library.id]?.failure != nil
        }

        let last = try XCTUnwrap(updates.last)
        XCTAssertEqual(last.statuses[library.id]?.fromCache, true)
        XCTAssertEqual(last.result.books.map(\.title), ["Cached 4"])
        XCTAssertEqual(last.result.unifiedOffsets[library.id]?.searchObjectSource, "http://public_example/3")
    }

    /// What the search cache has is shown before the server answers.
    func testTheCacheIsShownBeforeTheServerAnswers() async throws {
        try cacheBooks([1, 2], total: 2, of: mockLibrary1, source: "http://localhost/1")
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: offlineCriteria)

        let updates = await collectUpdates(for: key) { _ in true }

        let first = try XCTUnwrap(updates.first)
        XCTAssertEqual(first.statuses[mockLibrary1.id]?.loading, true)
        XCTAssertEqual(first.result.books.map(\.title), ["Cached 1", "Cached 2"])
    }
}

// Concrete Mock Repository for testing
class MockSearchCacheRepository: SearchCacheRepository {
    private let lock = NSRecursiveLock()
    
    private var _cachedLibraryResults: [String: LibraryCachedResult] = [:]
    private var _booksByLibrary: [String: [Int32: CalibreBook]] = [:]
    var localSearchResult = LocalLibrarySearchResult()

    private func makeKey(libraryId: String, search: String, sortBy: SortCriteria, sortAsc: Bool, filters: [String: Set<String>]) -> String {
        let filterStr = filters.keys.sorted().map { "\($0):\(filters[$0]?.sorted() ?? [])" }.joined(separator: ",")
        return "\(libraryId)|\(search)|\(sortBy.rawValue)|\(sortAsc)|\(filterStr)"
    }
    
    func fetchLibraryCachedResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) throws -> LibraryCachedResult? {
        lock.lock()
        defer { lock.unlock() }
        let key = makeKey(libraryId: libraryId, search: search, sortBy: sortBy, sortAsc: sortAsc, filters: filters)
        guard var cached = _cachedLibraryResults[key] else { return nil }
        let storedBooks = _booksByLibrary[libraryId] ?? [:]
        cached.sources = cached.sources.mapValues { source in
            let fallbackBooks = source.books.reduce(into: [Int32: CalibreBook]()) { partialResult, book in
                partialResult[book.id] = book
            }
            let books = source.bookIds.compactMap { storedBooks[$0] ?? fallbackBooks[$0] }
            return LibrarySourceSearchResult(
                generation: source.generation,
                totalNumber: source.totalNumber,
                bookIds: source.bookIds,
                books: books
            )
        }
        return cached
    }
    
    func saveLibrarySourceResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>],
        sourceUrl: String,
        result: LibrarySourceSearchResult
    ) throws {
        lock.lock()
        let key = makeKey(libraryId: libraryId, search: search, sortBy: sortBy, sortAsc: sortAsc, filters: filters)
        var cached = _cachedLibraryResults[key] ?? LibraryCachedResult(
            libraryId: libraryId,
            search: search,
            sortBy: sortBy,
            sortAsc: sortAsc,
            filters: filters,
            sources: [:]
        )
        cached.sources[sourceUrl] = result
        _cachedLibraryResults[key] = cached

        if !result.books.isEmpty {
            var books = _booksByLibrary[libraryId] ?? [:]
            for book in result.books {
                books[book.id] = book
            }
            _booksByLibrary[libraryId] = books
        }
        
        lock.unlock()
    }

    func fetchBooks(
        library: CalibreLibrary,
        bookIds: [Int32]
    ) throws -> [Int32: CalibreBook] {
        lock.lock()
        defer { lock.unlock() }
        let books = _booksByLibrary[library.id] ?? [:]
        return bookIds.reduce(into: [Int32: CalibreBook]()) { partialResult, bookId in
            partialResult[bookId] = books[bookId]
        }
    }

    func searchLocalLibrary(
        library: CalibreLibrary,
        criteria: SearchCriteria,
        offset: Int,
        limit: Int
    ) throws -> LocalLibrarySearchResult {
        lock.lock()
        defer { lock.unlock() }
        var result = localSearchResult
        result.offset = offset
        result.num = result.bookIds.count
        return result
    }

    func writeMetadataEntries(
        library: CalibreLibrary,
        entries: [String: CalibreBookEntry?],
        json: NSDictionary?
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        var books = _booksByLibrary[library.id] ?? [:]
        entries.forEach { key, entry in
            guard let entry = entry, let bookId = Int32(key) else { return }
            var book = books[bookId] ?? CalibreBook(id: bookId, library: library)
            let root = json?[key] as? NSDictionary ?? NSDictionary()
            book.applyMetadataValue(CalibreBookMetadataValue(entry: entry, root: root))
            books[bookId] = book
        }
        _booksByLibrary[library.id] = books
    }
}

@MainActor
class MockLibraryProvider: LibraryProvider {
    var libraries: [String: CalibreLibrary] = [:]
    
    func getLibraries() -> [String: CalibreLibrary] {
        return libraries
    }
    
    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return true
    }
    
    func isServerReachable(server: CalibreServer) -> Bool {
        return true
    }
}
