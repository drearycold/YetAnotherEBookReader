//
//  GoodreadsSyncConnector.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/9.
//

import Foundation

struct DSReaderHelperConnector {
    let calibreServerService: CalibreServerService
    let server: CalibreServer
    let dsreaderHelperServer: CalibreServerDSReaderHelper
    let goodreadsSync: CalibreGoodreadsSyncPrefs.PluginPrefs?

    let metadataQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Book Metadata queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var urlSession: URLSession {
        calibreServerService.urlSession(server: server)
    }

    func endpointConfiguration() -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var urlComponents = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/configuration")

        return urlComponents
    }

    func endpointConfigurationV1(libraryKey: String) -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var urlComponents = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/1/configuration/\(libraryKey)")

        return urlComponents
    }

    func endpointBaseUrlAddRemove(goodreads_id: String, shelfName: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        guard let profileName = goodreadsSync?.profileName else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/grsync/add_remove_book_to_shelf")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: profileName),
            URLQueryItem(name: "shelf_name", value: shelfName)
        ]

        return urlComponents
    }

    func endpointDictLookup() -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var urlComponents = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/dict_viewer/lookup")

        return urlComponents
    }

    func endpointAdvancedQA() -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var components = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        components.port = dsreaderHelperServer.port
        components.path.append("/dshelper/2/qa/query")
        return components
    }

    func endpointAdvancedQAStatus() -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var components = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        components.port = dsreaderHelperServer.port
        components.path.append("/dshelper/2/qa/status")
        return components
    }

    func endpointAdvancedQASyncJobs(page: Int, pageSize: Int, status: String? = nil,
                                    libraryId: String? = nil) -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var components = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        components.port = dsreaderHelperServer.port
        components.path.append("/dshelper/2/qa/sync-jobs")
        components.queryItems = [
            URLQueryItem(name: "page", value: max(1, page).description),
            URLQueryItem(name: "page_size", value: min(max(1, pageSize), 100).description)
        ]
        if let status, !status.isEmpty { components.queryItems?.append(.init(name: "status", value: status)) }
        if let libraryId, !libraryId.isEmpty {
            components.queryItems?.append(.init(name: "library_id", value: libraryId))
        }
        return components
    }

    func endpointAdvancedQASyncJob(jobId: Int, page: Int, pageSize: Int) -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var components = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        components.port = dsreaderHelperServer.port
        components.path.append("/dshelper/2/qa/sync-job/\(jobId)")
        components.queryItems = [
            URLQueryItem(name: "page", value: max(1, page).description),
            URLQueryItem(name: "page_size", value: min(max(1, pageSize), 500).description)
        ]
        return components
    }

    func queryAdvancedQAStatus() async throws -> AdvancedQAStatus {
        guard let url = endpointAdvancedQAStatus()?.url else {
            throw CalibreAPIError.invalidURL("queryAdvancedQAStatus")
        }
        let request = URLRequest(url: url)
        let (data, _) = try await calibreServerService.validatedData(for: request, server: server)
        return try JSONDecoder().decode(AdvancedQAStatus.self, from: data)
    }

    func queryAdvancedQASyncJobs(page: Int = 1, pageSize: Int = 50, status: String? = nil,
                                 libraryId: String? = nil) async throws -> AdvancedQASyncJobsPage {
        guard let url = endpointAdvancedQASyncJobs(page: page, pageSize: pageSize,
                                                   status: status, libraryId: libraryId)?.url else {
            throw CalibreAPIError.invalidURL("queryAdvancedQASyncJobs")
        }
        let (data, _) = try await calibreServerService.validatedData(for: URLRequest(url: url), server: server)
        return try JSONDecoder().decode(AdvancedQASyncJobsPage.self, from: data)
    }

    func queryAdvancedQASyncJob(jobId: Int, page: Int = 1,
                                pageSize: Int = 100) async throws -> AdvancedQASyncJobDetailPage {
        guard let url = endpointAdvancedQASyncJob(jobId: jobId, page: page, pageSize: pageSize)?.url else {
            throw CalibreAPIError.invalidURL("queryAdvancedQASyncJob")
        }
        let (data, _) = try await calibreServerService.validatedData(for: URLRequest(url: url), server: server)
        return try JSONDecoder().decode(AdvancedQASyncJobDetailPage.self, from: data)
    }

    func detectAdvancedQAAvailability() async -> AdvancedQAAvailability {
        await detectAdvancedQAStatus().availability
    }

    func detectAdvancedQAStatus() async -> AdvancedQAStatusDetection {
        do {
            let status = try await queryAdvancedQAStatus()
            return .init(status: status, availability: AdvancedQAAvailability(status: status))
        } catch let error as CalibreAPIError {
            if case .httpStatus(404, _) = error { return .init(status: nil, availability: .unsupported) }
            return .init(status: nil, availability: .unavailable)
        } catch {
            return .init(status: nil, availability: .unavailable)
        }
    }

    func queryAdvancedQA(_ payload: AdvancedQARequest) async throws -> AdvancedQAResponse {
        guard let url = endpointAdvancedQA()?.url else {
            throw CalibreAPIError.invalidURL("queryAdvancedQA")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(AdvancedQAWireRequest(payload))
        let (data, _) = try await calibreServerService.validatedData(for: request, server: server)
        return try JSONDecoder().decode(AdvancedQAWireResponse.self, from: data).response
    }

    func endpointBaseUrlPrecent(goodreads_id: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        guard let profileName = goodreadsSync?.profileName else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/grsync/update_reading_progress")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: profileName)
        ]

        return urlComponents
    }

    func refreshConfiguration() async throws -> (id: String, port: Int, data: Data) {
        guard let url = endpointConfiguration()?.url else {
            throw URLError(.badURL)
        }

        return try await refreshConfiguration(from: url)
    }

    private func refreshConfiguration(from url: URL) async throws -> (id: String, port: Int, data: Data) {
        let request = URLRequest(url: url)
        let (data, _) = try await calibreServerService.validatedData(for: request, server: server)
        return (id: server.uuid.uuidString, port: dsreaderHelperServer.port, data: data)
    }

    func refreshConfiguration(_ libraryKey: String) async throws -> (CalibreDSReaderHelperConfiguration, Data) {
        guard let url = endpointConfigurationV1(libraryKey: libraryKey)?.url else {
            throw URLError(.badURL)
        }

        let request = URLRequest(url: url)
        let (data, _) = try await calibreServerService.validatedData(for: request, server: server)
        let config = try JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: data)

        return (config, data)
    }

    func addToShelf(goodreads_id: String, shelfName: String) async throws {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            throw CalibreAPIError.invalidURL("addToShelf")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "add"))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("addToShelf")
        }

        let request = URLRequest(url: url)
        _ = try await calibreServerService.validatedData(for: request, server: server)
    }

    func removeFromShelf(goodreads_id: String, shelfName: String) async throws {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            throw CalibreAPIError.invalidURL("removeFromShelf")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "remove"))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("removeFromShelf")
        }

        let request = URLRequest(url: url)
        _ = try await calibreServerService.validatedData(for: request, server: server)
    }

    func updateReadingProgress(goodreads_id: String, progress: Double) async throws {
        guard var endpointBaseUrl = endpointBaseUrlPrecent(goodreads_id: goodreads_id) else {
            throw CalibreAPIError.invalidURL("updateReadingProgress")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "percent", value: progress.description))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("updateReadingProgress")
        }

        let request = URLRequest(url: url)
        _ = try await calibreServerService.validatedData(for: request, server: server)
    }

}

private struct AdvancedQAWireRequest: Encodable {
    struct Book: Encodable { var libraryId: String; var bookId: Int; var format: String
        enum CodingKeys: String, CodingKey { case format; case libraryId = "library_id"; case bookId = "book_id" }
    }
    struct Position: Encodable { var spineIndex: Int?; var pageNumber: Int?
        enum CodingKeys: String, CodingKey { case spineIndex = "spine_index"; case pageNumber = "page_number" }
    }
    struct Selection: Encodable { var text: String }
    struct Sources: Encodable { var dictionary: Bool }
    struct ExternalContext: Encodable {
        var source: String; var title: String; var locator: [String: JSONValue]; var text: String
    }

    var query: String
    var mode: AdvancedQAMode
    var responseLanguage: String
    var book: Book
    var position: Position?
    var selection: Selection
    var retrievalScope: AdvancedQARetrievalScopeSelection
    var evidenceSources: Sources
    var externalContexts: [ExternalContext]
    var topK: Int

    enum CodingKeys: String, CodingKey {
        case query, mode, book, position, selection
        case responseLanguage = "response_language"
        case retrievalScope = "retrieval_scope"
        case evidenceSources = "evidence_sources"
        case externalContexts = "external_contexts"
        case topK = "top_k"
    }

    init(_ request: AdvancedQARequest) {
        let context = request.readerContext
        let bookId = Int(context.book.id.split(separator: "^").first ?? "") ?? 0
        book = Book(libraryId: context.book.libraryId ?? "", bookId: bookId,
                    format: context.book.format.uppercased())
        query = request.query
        mode = request.mode
        responseLanguage = request.responseLanguage
        selection = Selection(text: context.selection.text)
        if let page = context.location.page {
            position = context.location.engine == "folio"
                ? Position(spineIndex: max(0, page - 1), pageNumber: nil)
                : Position(spineIndex: nil, pageNumber: page)
        } else {
            position = nil
        }
        retrievalScope = request.retrievalScope
        evidenceSources = Sources(dictionary: request.options.useDictionary)
        externalContexts = request.referenceCandidates.map { candidate in
            var locator = [String: JSONValue]()
            if let cfi = candidate.location.cfi { locator = ["type": .string("epub_cfi"), "value": .string(cfi)] }
            else if let page = candidate.location.page { locator = ["type": .string("page"), "value": .number(Double(page))] }
            return ExternalContext(source: "reference", title: candidate.title,
                                   locator: locator, text: candidate.snippet)
        }
        topK = request.options.maxEvidence
    }
}

private struct AdvancedQAWireResponse: Decodable {
    struct Item: Decodable {
        var source: String?
        var title: String?
        var text: String?
        var content: String?
        var locator: [String: JSONValue]?
    }

    var answer: String
    var evidence: [Item] = []
    var contexts: [Item] = []
    var citations: [JSONValue] = []
    var warnings: [String] = []

    var response: AdvancedQAResponse {
        let all = evidence + contexts
        let mapped = all.enumerated().map { index, item in
            Evidence(id: "ev-\(index + 1)", source: item.source ?? "rag",
                     title: item.title ?? "Evidence", content: item.text ?? item.content ?? "",
                     location: nil, metadata: item.locator ?? [:])
        }
        return AdvancedQAResponse(
            qaApiVersion: 2,
            answer: QAAnswer(text: answer, citations: citations.map(String.init(describing:))),
            cards: [], evidence: mapped, actions: [], warnings: warnings
        )
    }
}
