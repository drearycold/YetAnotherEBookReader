//
//  PDFSearchController.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

@available(iOS 16.0, macCatalyst 16.0, *)
class PDFSearchController: NSObject {
    private weak var surface: PDFReaderSurface?
    private var pdfView: YabrPDFView? { surface?.activeView }
    private var yabrPDFMetaSource: YabrPDFMetaSource?

    init(surface: PDFReaderSurface, metaSource: YabrPDFMetaSource?) {
        self.surface = surface
        self.yabrPDFMetaSource = metaSource
    }

    deinit {
        pdfView?.document?.cancelFindString()
    }

    func search(query: String, completion: @escaping ([PDFSelection]) -> Void) {
        guard let document = pdfView?.document else {
            completion([])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let selections = document.findString(query, withOptions: [.caseInsensitive])
            DispatchQueue.main.async {
                completion(selections)
            }
        }
    }
}

/// Recent search queries, newest first, as FolioReader's
/// `FolioReaderSearchHistoryStore`: a query is kept once (case and diacritics
/// ignored), and only the last `maxCount`. Held for the reader session only,
/// as FolioReader's history is in this app (its preference provider does not
/// persist it).
struct PDFSearchHistory: Equatable {
    static let maxCount = 100

    private(set) var queries: [String] = []

    mutating func record(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        queries.removeAll { Self.isEquivalent($0, query) }
        queries.insert(query, at: 0)
        queries = Array(queries.prefix(Self.maxCount))
    }

    mutating func remove(_ query: String) {
        queries.removeAll { $0 == query }
    }

    private static func isEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
