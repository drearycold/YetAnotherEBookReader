import Foundation
import FolioReaderKit
import PDFKit

enum AdvancedQAContextBuilder {
    struct FolioLookup {
        var context: ReaderSelectionContext
        var candidates: [ReferenceCandidate]
    }

    struct PDFInput {
        var selection: String
        var page: Int?
        var chapter: String?
        var visibleText: String?
        var progress: Double?
    }

    static func pdf(book: CalibreBook, input: PDFInput) -> ReaderSelectionContext {
        makeContext(
            book: book,
            selection: input.selection,
            engine: "pdf",
            chapter: input.chapter,
            tocPath: input.chapter.map { [$0] } ?? [],
            page: input.page,
            progress: input.progress,
            visible: input.visibleText
        )
    }

    static func folio(
        book: CalibreBook,
        selection: String,
        location: FolioReaderLocatorResult?
    ) -> ReaderSelectionContext {
        makeContext(
            book: book,
            selection: selection,
            engine: "folio",
            chapter: location?.tocPath.last,
            tocPath: location?.tocPath ?? [],
            page: location?.page,
            href: location?.href,
            fragmentId: location?.fragmentId,
            cfi: location?.cfi,
            progress: location?.chapterProgress,
            visible: location?.context
        )
    }

    static func readium(
        book: CalibreBook,
        selection: String,
        chapter: String? = nil,
        href: String? = nil,
        progress: Double? = nil,
        visibleText: String? = nil
    ) -> ReaderSelectionContext {
        makeContext(
            book: book,
            selection: selection,
            engine: "readium",
            chapter: chapter,
            tocPath: chapter.map { [$0] } ?? [],
            page: nil,
            href: href,
            progress: progress,
            visible: visibleText
        )
    }

    static func folioCandidates(book: CalibreBook, results: [FolioReaderLocatorResult]) -> [ReferenceCandidate] {
        results.enumerated().map { index, result in
            ReferenceCandidate(
                id: "folio-\(index)",
                source: "folio_reference",
                bookId: book.inShelfId,
                title: result.tocPath.last ?? book.title,
                snippet: result.context ?? result.text ?? "",
                location: location(engine: "folio", chapter: result.tocPath.last,
                                   tocPath: result.tocPath, page: result.page, href: result.href,
                                   fragmentId: result.fragmentId, cfi: result.cfi,
                                   progress: result.chapterProgress),
                score: 1.0
            )
        }
    }

    static func folioReferenceBoundary(
        location: FolioReaderLocatorResult?
    ) -> FolioReaderLocatorQuery? {
        guard let location, location.page > 0 else { return nil }
        return FolioReaderLocatorQuery(
            cfi: location.cfi,
            page: location.page,
            href: location.href,
            fragmentId: location.fragmentId
        )
    }

    static func folioLookup(
        book: CalibreBook,
        selection: String,
        resolver: FolioReaderReferenceResolving?
    ) async -> FolioLookup {
        let selectedLocation = await resolver?.selectedTextLocation()
        let currentLocation = selectedLocation == nil ? await resolver?.currentLocation() : nil
        let location = selectedLocation ?? currentLocation
        let results: [FolioReaderLocatorResult]
        if let resolver, let boundary = folioReferenceBoundary(location: location) {
            results = await resolver.reverseLookup(text: selection, before: boundary)
        } else {
            results = []
        }
        return FolioLookup(
            context: folio(book: book, selection: selection, location: location),
            candidates: folioCandidates(book: book, results: results)
        )
    }

    private static func makeContext(
        book: CalibreBook, selection: String, engine: String, chapter: String?,
        tocPath: [String], page: Int?, href: String? = nil, fragmentId: String? = nil,
        cfi: String? = nil, progress: Double?, visible: String?
    ) -> ReaderSelectionContext {
        ReaderSelectionContext(
            book: .init(id: book.inShelfId, libraryId: book.library.key, title: book.title,
                        authors: book.authors, format: format(for: book),
                        series: book.series.isEmpty ? nil : book.series),
            selection: .init(text: selection, normalizedText: nil, language: nil),
            location: location(engine: engine, chapter: chapter, tocPath: tocPath, page: page,
                               href: href, fragmentId: fragmentId, cfi: cfi, progress: progress),
            surroundingText: .init(before: "", after: "", visible: visible)
        )
    }

    private static func location(
        engine: String, chapter: String?, tocPath: [String], page: Int?, href: String? = nil,
        fragmentId: String? = nil, cfi: String? = nil, progress: Double?
    ) -> ReaderSelectionContext.Location {
        .init(engine: engine, chapter: chapter, tocPath: tocPath, page: page, href: href,
              fragmentId: fragmentId, cfi: cfi, cfiStart: nil, cfiEnd: nil, progress: progress)
    }

    private static func format(for book: CalibreBook) -> String {
        let formats = book.formats.keys.map { $0.lowercased() }
        return ["epub", "pdf", "cbz"].first(where: formats.contains) ?? "unknown"
    }
}
