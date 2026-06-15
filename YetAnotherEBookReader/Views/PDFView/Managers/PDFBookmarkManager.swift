//
//  PDFBookmarkManager.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

class PDFBookmarkManager {
    private weak var pdfView: YabrPDFView?
    private var yabrPDFMetaSource: YabrPDFMetaSource?

    init(pdfView: YabrPDFView, metaSource: YabrPDFMetaSource?) {
        self.pdfView = pdfView
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
