import Foundation
import ReadiumShared
import ReadiumStreamer

/// One immutable book/format/file per presentation; requests never reach another preview.
@MainActor
final class BookPreviewViewModel: ObservableObject, Identifiable {
    enum ContentsState: Equatable {
        case loading, loaded(String), empty, generating, failed(String)
    }

    let id = UUID()
    let book: CalibreBook
    let readerInfo: ReaderInfo
    @Published private(set) var contentsState: ContentsState = .loading
    private let loadManifest: () async throws -> Data
    private let loadLocalContents: () async throws -> String
    private var contentsTask: Task<Void, Never>?
    private var requestID: UUID?

    init(book: CalibreBook, readerInfo: ReaderInfo,
         loadManifest: @escaping () async throws -> Data,
         loadLocalContents: @escaping () async throws -> String) {
        self.book = book
        self.readerInfo = readerInfo
        self.loadManifest = loadManifest
        self.loadLocalContents = loadLocalContents
    }

    convenience init(container: AppContainer, book: CalibreBook, readerInfo: ReaderInfo) {
        self.init(book: book, readerInfo: readerInfo,
            loadManifest: { try await container.calibreServerService.getBookManifest(book: book, format: readerInfo.format) },
            loadLocalContents: { try await Self.localContents(url: readerInfo.url) })
    }

    deinit { contentsTask?.cancel() }

    func start() {
        guard requestID == nil else { return }
        loadContents()
    }

    func loadContents() {
        cancel()
        let id = UUID()
        requestID = id
        contentsState = .loading
        let local = book.library.server.isLocal
        let savedManifest = book.formats[readerInfo.format.rawValue]?.manifest
        let loadManifest = loadManifest
        let loadLocalContents = loadLocalContents
        contentsTask = Task { [weak self] in
            let result: ContentsState
            do {
                if local {
                    let text = try await loadLocalContents()
                    result = text.isEmpty ? .empty : .loaded(text)
                } else if let savedManifest, case .loaded(let text) = Self.parseManifest(savedManifest) {
                    result = .loaded(text)
                } else {
                    do {
                        result = Self.parseManifest(try await loadManifest())
                    } catch {
                        try Task.checkCancellation()
                        // A downloaded book is also previewable without its server.
                        if let text = try? await loadLocalContents() {
                            result = text.isEmpty ? .empty : .loaded(text)
                        } else {
                            result = .failed("Could not load the table of contents. Check your connection and try again.")
                        }
                    }
                }
            } catch {
                result = .failed("Could not read this file. Try again or replace the file.")
            }
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.contentsState = result
            self.contentsTask = nil
        }
    }

    func cancel() {
        requestID = nil
        contentsTask?.cancel()
        contentsTask = nil
    }

    static func parseManifest(_ data: Data) -> ContentsState {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed("The server returned an invalid table of contents. Please try again.")
        }
        if root["aborted"] as? Bool == true || (root["traceback"] as? String)?.isEmpty == false {
            return .failed("The server could not generate the table of contents. Please try again.")
        }
        if let status = root["job_status"] as? String {
            if ["waiting", "running", "working"].contains(status) { return .generating }
            if ["failed", "error"].contains(status) { return .failed("The server could not generate the table of contents. Please try again.") }
        }
        guard let toc = root["toc"], !(toc is NSNull) else { return .empty }
        guard let node = toc as? [String: Any] else {
            return .failed("The server returned an invalid table of contents. Please try again.")
        }
        do {
            let text = try contents(node: node, level: 0, includeTitle: false)
            return text.isEmpty ? .empty : .loaded(text)
        } catch {
            return .failed("The server returned an invalid table of contents. Please try again.")
        }
    }

    private enum ContentsError: Error { case invalid }

    private static func contents(node: [String: Any], level: Int, includeTitle: Bool) throws -> String {
        guard level < 64 else { throw ContentsError.invalid }
        var text = ""
        if let title = node["title"], !(title is String), !(title is NSNull) { throw ContentsError.invalid }
        if includeTitle, let title = node["title"] as? String, !title.isEmpty {
            text = String(repeating: "  ", count: max(0, level - 1)) + title + "\n"
        }
        if let value = node["children"] {
            guard let children = value as? [[String: Any]] else { throw ContentsError.invalid }
            for child in children { text += try contents(node: child, level: level + 1, includeTitle: true) }
        }
        return text
    }

    /// Use the same publication parser as the Readium reader, without creating a reader/session.
    static func localContents(url: URL) async throws -> String {
        let client = DefaultHTTPClient()
        let retriever = AssetRetriever(httpClient: client)
        guard let absoluteURL = url.anyURL.absoluteURL else { throw ContentsError.invalid }
        let asset = try await retriever.retrieve(url: absoluteURL).get()
        try Task.checkCancellation()
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: client, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()))
        let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
        try Task.checkCancellation()
        func titles(_ links: [ReadiumShared.Link], level: Int = 0) -> String {
            guard level < 64 else { return "" }
            return links.map { link in
                let title = link.title.map { String(repeating: "  ", count: level) + $0 + "\n" } ?? ""
                return title + titles(link.children, level: level + 1)
            }.joined()
        }
        return titles(try await publication.tableOfContents().get())
    }
}
