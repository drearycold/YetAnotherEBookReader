//
//  PDFAnnotationManager.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

class PDFAnnotationManager {
    private weak var pdfView: YabrPDFView?
    private var yabrPDFMetaSource: YabrPDFMetaSource?

    init(pdfView: YabrPDFView, metaSource: YabrPDFMetaSource?) {
        self.pdfView = pdfView
        self.yabrPDFMetaSource = metaSource
    }

    func addHighlight(style: Int, selection: PDFSelection) {
        guard let pdfView = pdfView else { return }
        
        var pdfHighlightPageLocations = [PDFHighlight.PageLocation]()
        selection.pages.forEach { selectionPage in
            guard let selectionPageNumber = selectionPage.pageRef?.pageNumber else { return }
            var pdfHighlightPage = PDFHighlight.PageLocation(page: selectionPageNumber, ranges: [])
            for i in 0..<selection.numberOfTextRanges(on: selectionPage) {
                let selectionPageRange = selection.range(at: i, on: selectionPage)
                pdfHighlightPage.ranges.append(selectionPageRange)
            }
            pdfHighlightPageLocations.append(pdfHighlightPage)
        }
        
        let pdfHighlight = PDFHighlight(
            uuid: UUID(),
            pos: pdfHighlightPageLocations,
            type: style,
            content: selection.string ?? "No Content",
            date: Date()
        )
        
        yabrPDFMetaSource?.yabrPDFHighlights(pdfView, update: pdfHighlight)
        pdfView.injectHighlight(highlight: pdfHighlight)
    }

    func injectAllHighlights() {
        guard let pdfView = pdfView else { return }
        yabrPDFMetaSource?.yabrPDFHighlights(pdfView).forEach { highlight in
            pdfView.injectHighlight(highlight: highlight)
        }
    }
}
