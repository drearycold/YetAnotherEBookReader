import XCTest
import FolioReaderKit
@testable import YetAnotherEBookReader

@MainActor
final class AdvancedQATests: XCTestCase {
    private var library: CalibreLibrary!
    private var book: CalibreBook!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "advancedQA.retrievalScope.kind")
        let server = CalibreServer(uuid: UUID(), name: "Server", baseUrl: "http://192.168.11.65:8080",
                                   hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        library = CalibreLibrary(server: server, key: "main", name: "Main")
        book = CalibreBook(id: 42, library: library)
        book.title = "QA Book"
        book.authors = ["Author"]
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "advancedQA.retrievalScope.kind")
        super.tearDown()
    }

    private func scope(
        _ kind: String,
        requires: [String] = [],
        parameters: [String] = [],
        spoilerSafe: Bool = false,
        spoilerRisk: String = "full_text"
    ) -> AdvancedQARetrievalScopeCapability {
        .init(kind: kind,
              labelKey: "missing.\(kind).label",
              descriptionKey: "missing.\(kind).description",
              fallbackLabel: "Label \(kind)",
              fallbackDescription: "Description \(kind)",
              spoilerSafe: spoilerSafe,
              spoilerRisk: spoilerRisk,
              requires: requires,
              parameters: parameters)
    }

    func testRequestAndResponseCodableRoundTrip() throws {
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "term", page: 12, chapter: "Chapter", visibleText: "visible", progress: 0.5)
        )
        let request = AdvancedQARequest(query: "Explain", mode: .explain, readerContext: context,
                                        referenceCandidates: [])
        XCTAssertEqual(try JSONDecoder().decode(AdvancedQARequest.self, from: JSONEncoder().encode(request)), request)

        let response = AdvancedQAResponse(qaApiVersion: 2, answer: .init(text: "Answer", citations: ["ev-1"]),
                                          cards: [], evidence: [], actions: [], warnings: [])
        XCTAssertEqual(try JSONDecoder().decode(AdvancedQAResponse.self, from: JSONEncoder().encode(response)), response)
    }

    func testPDFContextIncludesPageOutlineAndVisibleText() {
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "selected", page: 7, chapter: "Part One",
                         visibleText: "whole page", progress: 0.25)
        )
        XCTAssertEqual(context.book.id, book.inShelfId)
        XCTAssertEqual(context.selection.text, "selected")
        XCTAssertEqual(context.location.engine, "pdf")
        XCTAssertEqual(context.location.page, 7)
        XCTAssertEqual(context.location.tocPath, ["Part One"])
        XCTAssertEqual(context.surroundingText.visible, "whole page")
    }

    func testFolioContextAndCandidatesMapResolverResults() {
        let result = FolioReaderLocatorResult(page: 3, href: "chapter.xhtml", cfi: "epubcfi(/6/2)",
                                              fragmentId: "anchor", text: "term", context: "around term",
                                              tocPath: ["Part", "Chapter"], chapterProgress: 0.4)
        let context = AdvancedQAContextBuilder.folio(book: book, selection: "term", location: result)
        let candidates = AdvancedQAContextBuilder.folioCandidates(book: book, results: [result])
        XCTAssertEqual(context.location.engine, "folio")
        XCTAssertEqual(context.location.cfi, result.cfi)
        XCTAssertEqual(context.location.tocPath, result.tocPath)
        XCTAssertEqual(candidates.first?.source, "folio_reference")
        XCTAssertEqual(candidates.first?.snippet, "around term")
    }

    func testFolioReferenceBoundaryUsesCurrentPageAndCFI() {
        let location = FolioReaderLocatorResult(
            page: 3,
            href: "chapter.xhtml",
            cfi: "epubcfi(/6/4)",
            fragmentId: "selection"
        )

        let query = AdvancedQAContextBuilder.folioReferenceBoundary(location: location)

        XCTAssertEqual(query?.page, 3)
        XCTAssertEqual(query?.cfi, "epubcfi(/6/4)")
        XCTAssertEqual(query?.href, "chapter.xhtml")
        XCTAssertEqual(query?.fragmentId, "selection")
        XCTAssertNil(AdvancedQAContextBuilder.folioReferenceBoundary(location: nil))
    }

    func testFolioLookupUsesSelectedBoundaryAndFailsClosedWithoutLocation() async {
        let selected = FolioReaderLocatorResult(page: 2, cfi: "epubcfi(/4/6)")
        let resolver = AdvancedQATestReferenceResolver(
            current: .init(page: 5, cfi: "epubcfi(/10/2)"),
            selected: selected,
            results: [.init(page: 1, cfi: "epubcfi(/2/2)", context: "earlier")]
        )

        let lookup = await AdvancedQAContextBuilder.folioLookup(
            book: book,
            selection: "term",
            resolver: resolver
        )

        XCTAssertEqual(resolver.receivedBoundary?.page, selected.page)
        XCTAssertEqual(resolver.receivedBoundary?.cfi, selected.cfi)
        XCTAssertEqual(lookup.candidates.count, 1)

        let locationless = AdvancedQATestReferenceResolver(current: nil, selected: nil, results: [])
        let locationlessLookup = await AdvancedQAContextBuilder.folioLookup(
            book: book,
            selection: "term",
            resolver: locationless
        )
        XCTAssertEqual(locationless.reverseLookupCallCount, 0)
        XCTAssertTrue(locationlessLookup.candidates.isEmpty)
    }

    func testReadiumMinimumContext() {
        let context = AdvancedQAContextBuilder.readium(
            book: book, selection: "", chapter: "Chapter", href: "chapter.xhtml", progress: 0.3
        )
        XCTAssertEqual(context.location.engine, "readium")
        XCTAssertEqual(context.location.href, "chapter.xhtml")
        XCTAssertEqual(context.location.progress, 0.3)
        XCTAssertEqual(context.book.libraryId, "main")
    }

    func testFolioAdvancedQAMenuIsVisibleAndNamed() {
        let configuration = FolioReaderConfig()
        FolioAdvancedQAMenuConfiguration.apply(to: configuration, isAvailable: true)
        XCTAssertTrue(configuration.enableMDictViewer)
        XCTAssertEqual(configuration.localizedMDictMenu, "Reader QA")

        FolioAdvancedQAMenuConfiguration.apply(to: configuration, isAvailable: false)
        XCTAssertFalse(configuration.enableMDictViewer)
    }

    func testDSReaderHelperConfigurationDecodesWhenLegacyFieldsAreMissing() throws {
        let data = Data(#"""
        {
          "dsreader_helper_prefs":{"plugin_prefs":{"Options":{
            "servicePort":8081,
            "goodreadsSyncEnabled":true,
            "dictViewerEnabled":true,
            "dictViewerLibraryName":"Dictionary",
            "cortexEnabled":true
          }}},
          "count_pages_prefs":{"plugin_prefs":{"Options":{}}},
          "goodreads_sync_prefs":{"plugin_prefs":{
            "Goodreads":{"dateReadColumn":"","ratingColumn":"","readingProgressColumn":"","reviewTextColumn":"","tagMappingColumn":"tags"},
            "SchemaVersion":1.68,
            "Users":{}
          }}
        }
        """#.utf8)

        let configuration = try JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: data)
        let options = try XCTUnwrap(configuration.dsreader_helper_prefs?.plugin_prefs.Options)
        XCTAssertEqual(options.servicePort, 8081)
        XCTAssertTrue(options.dictViewerEnabled)
        XCTAssertEqual(options.dictViewerLibraryName, "Dictionary")
        XCTAssertEqual(configuration.count_pages_prefs?.library_config, [:])
    }

    func testAdvancedQAAvailabilityUILabels() {
        XCTAssertEqual(AdvancedQAAvailability.ready.title, "Ready")
        XCTAssertEqual(AdvancedQAAvailability.disabled.title, "Disabled")
        XCTAssertEqual(AdvancedQAAvailability.unavailable.detail, "Cortex unavailable")
        XCTAssertEqual(AdvancedQAAvailability.unsupported.detail, "Update DSReaderHelper")
        XCTAssertEqual(AdvancedQAAvailability.unknown.title, "Not checked")
    }

    func testAdvancedQAStatusDecodesDynamicScopesAndLegacyStatus() throws {
        let data = Data(#"{"enabled":true,"state":"ready","retrieval_scopes":{"version":1,"default":"current_book_read","items":[{"kind":"current_book_read","label_key":"advanced_qa.scope.current_book_read.label","description_key":"advanced_qa.scope.current_book_read.description","fallback_label":"Current book (read portion)","fallback_description":"Search read content.","spoiler_safe":true,"spoiler_risk":"read_boundary","requires":["position"],"parameters":[]}]}}"#.utf8)
        let status = try JSONDecoder().decode(AdvancedQAStatus.self, from: data)
        XCTAssertEqual(status.retrievalScopes?.version, 1)
        XCTAssertEqual(status.retrievalScopes?.defaultKind, "current_book_read")
        XCTAssertEqual(status.retrievalScopes?.items.first?.localizedLabel, "Current book (read portion)")

        let legacy = try JSONDecoder().decode(AdvancedQAStatus.self,
                                              from: Data(#"{"enabled":true,"state":"ready"}"#.utf8))
        XCTAssertTrue(legacy.isReady)
        XCTAssertNil(legacy.retrievalScopes)
    }

    func testDynamicScopeSelectionUsesServerDefaultAndRejectsRemovedSavedKind() {
        UserDefaults.standard.set("removed_scope", forKey: "advancedQA.retrievalScope.kind")
        let scopes = AdvancedQARetrievalScopes(version: 1, defaultKind: "current_book",
                                               items: [scope("current_book"), scope("all_ingested")])
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "term", page: 1, chapter: nil, visibleText: nil, progress: 0.1)
        )
        let model = AdvancedQAViewModel(context: context, retrievalScopes: scopes) { _ in
            throw URLError(.badServerResponse)
        }
        XCTAssertEqual(model.retrievalScopes.items.map(\.kind), ["current_book", "all_ingested"])
        XCTAssertEqual(model.selectedScopeKind, "current_book")
        XCTAssertFalse(model.retrievalScopes.isLegacy)
    }

    func testScopeRequirementsAndSpoilerDescriptions() {
        let scopes = AdvancedQARetrievalScopes(
            version: 1,
            defaultKind: "current_book",
            items: [
                scope("current_book_read", requires: ["position"], spoilerSafe: true, spoilerRisk: "read_boundary"),
                scope("current_series", requires: ["series_metadata"]),
                scope("annotations", requires: ["external_contexts"], spoilerSafe: true, spoilerRisk: "client_controlled"),
                scope("all_ingested", spoilerRisk: "highest")
            ]
        )
        let context = AdvancedQAContextBuilder.readium(book: book, selection: "term")
        let model = AdvancedQAViewModel(context: context, retrievalScopes: scopes) { _ in
            throw URLError(.badServerResponse)
        }
        XCTAssertEqual(model.unavailableReason(for: scopes.items[0]), "Requires current reading position.")
        XCTAssertEqual(model.unavailableReason(for: scopes.items[1]), "Requires book series metadata.")
        XCTAssertEqual(model.unavailableReason(for: scopes.items[2]), "Requires reader annotations or references.")
        XCTAssertTrue(scopes.items[0].spoilerDescription.contains("excluded"))
        XCTAssertTrue(scopes.items[3].spoilerDescription.contains("Highest"))
    }

    func testLegacyScopeFallbackIsExplicit() {
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "term", page: 2, chapter: nil, visibleText: nil, progress: 0.1)
        )
        let model = AdvancedQAViewModel(context: context) { _ in throw URLError(.badServerResponse) }
        XCTAssertTrue(model.retrievalScopes.isLegacy)
        XCTAssertEqual(model.selectedScopeKind, "current_book_read")
    }

    func testRelatedAndSelectedScopeParametersBuildRequests() async {
        let related = scope("related_books", parameters: ["relations", "combine", "include_current_book"])
        let selected = scope("selected_books", parameters: ["books", "book_ids"])
        let scopes = AdvancedQARetrievalScopes(version: 1, defaultKind: related.kind, items: [related, selected])
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "term", page: 1, chapter: nil, visibleText: nil, progress: 0.1)
        )
        var requests = [AdvancedQARequest]()
        let model = AdvancedQAViewModel(context: context, retrievalScopes: scopes) { request in
            requests.append(request)
            return AdvancedQAResponse(qaApiVersion: 2, answer: .init(text: "ok", citations: []),
                                      cards: [], evidence: [], actions: [], warnings: [])
        }
        model.relatedByAuthor = true
        model.relatedByLibrary = true
        model.relatedCombine = "any"
        model.includeCurrentBook = true
        await model.submit()
        XCTAssertEqual(requests.last?.retrievalScope.relations.map(\.kind), ["same_author", "same_library"])
        XCTAssertEqual(requests.last?.retrievalScope.combine, "any")
        XCTAssertEqual(requests.last?.retrievalScope.includeCurrentBook, true)

        model.selectedScopeKind = "selected_books"
        model.selectedBookIDs = "12, 34"
        model.selectedBooks = "archive:7:epub"
        await model.submit()
        XCTAssertEqual(requests.last?.retrievalScope.kind, "selected_books")
        XCTAssertEqual(requests.last?.retrievalScope.bookIds, [12, 34])
        XCTAssertEqual(requests.last?.retrievalScope.books.first?.libraryId, "archive")
        XCTAssertEqual(requests.last?.retrievalScope.books.first?.bookId, 7)
        XCTAssertEqual(requests.last?.retrievalScope.books.first?.format, "EPUB")
    }

    func testViewModelLoadingAndSuccessStates() async {
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "term", page: 1, chapter: nil, visibleText: nil, progress: 0.1)
        )
        let expected = AdvancedQAResponse(qaApiVersion: 2, answer: .init(text: "Done", citations: []),
                                          cards: [], evidence: [], actions: [], warnings: [])
        let gate = AsyncStream<Void>.makeStream()
        let model = AdvancedQAViewModel(context: context) { _ in
            for await _ in gate.stream { break }
            return expected
        }
        let task = Task { await model.submit() }
        await Task.yield()
        XCTAssertEqual(model.state, .loading)
        gate.continuation.yield()
        gate.continuation.finish()
        await task.value
        XCTAssertEqual(model.state, .loaded(expected))
    }

    func testViewModelErrorState() async {
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "term", page: nil, chapter: nil, visibleText: nil, progress: nil)
        )
        let model = AdvancedQAViewModel(context: context) { _ in throw URLError(.cannotConnectToHost) }
        await model.submit()
        guard case .failed = model.state else { return XCTFail("Expected failed state") }
    }

    func testPresetModesAllowOptionalPromptWhileAskRequiresQuestion() {
        let context = AdvancedQAContextBuilder.pdf(
            book: book,
            input: .init(selection: "term", page: 1, chapter: nil, visibleText: nil, progress: 0.1)
        )
        let model = AdvancedQAViewModel(context: context) { _ in
            throw URLError(.badServerResponse)
        }

        XCTAssertEqual(model.query, "")
        model.mode = .explain
        XCTAssertTrue(model.canSubmit)
        model.mode = .translate
        XCTAssertTrue(model.canSubmit)
        model.mode = .define
        XCTAssertTrue(model.canSubmit)
        model.mode = .ask
        XCTAssertFalse(model.canSubmit)
        model.query = "Who is this?"
        XCTAssertTrue(model.canSubmit)
    }
}

private final class AdvancedQATestReferenceResolver: FolioReaderReferenceResolving {
    let current: FolioReaderLocatorResult?
    let selected: FolioReaderLocatorResult?
    let results: [FolioReaderLocatorResult]
    private(set) var receivedBoundary: FolioReaderLocatorQuery?
    private(set) var reverseLookupCallCount = 0

    init(current: FolioReaderLocatorResult?, selected: FolioReaderLocatorResult?,
         results: [FolioReaderLocatorResult]) {
        self.current = current
        self.selected = selected
        self.results = results
    }

    func currentLocation() async -> FolioReaderLocatorResult? { current }
    func selectedTextLocation() async -> FolioReaderLocatorResult? { selected }

    func reverseLookup(
        text: String,
        before query: FolioReaderLocatorQuery?
    ) async -> [FolioReaderLocatorResult] {
        reverseLookupCallCount += 1
        receivedBoundary = query
        return results
    }
}
