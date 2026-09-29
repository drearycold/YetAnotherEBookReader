//
//  PDFBookmarkManager.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

@available(iOS 16.0, macCatalyst 16.0, *)
class PDFBookmarkManager {
    private weak var surface: PDFReaderSurface?
    private var pdfView: YabrPDFView? { surface?.activeView }
    private var yabrPDFMetaSource: YabrPDFMetaSource?

    init(surface: PDFReaderSurface, metaSource: YabrPDFMetaSource?) {
        self.surface = surface
        self.yabrPDFMetaSource = metaSource
    }

    func addBookmark(completion: (() -> Void)? = nil) {
        defer {
            completion?()
        }
        guard let pdfView = pdfView,
              let destination = pdfView.currentDestination,
              let pageNumber = destination.page?.pageRef?.pageNumber
        else {
            return
        }
        
        yabrPDFMetaSource?.yabrPDFBookmarks(
            pdfView,
            update: PDFBookmark(
                pos: PDFBookmark.Location(page: pageNumber, offset: destination.point),
                title: yabrPDFMetaSource?.yabrPDFOutline(pdfView, for: pageNumber)?.label ?? "Page \(pageNumber)",
                date: Date()
            )
        )
    }
}
