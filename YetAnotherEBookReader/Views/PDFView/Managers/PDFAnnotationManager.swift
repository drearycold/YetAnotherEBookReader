//
//  PDFAnnotationManager.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

class PDFAnnotationManager {
    private weak var pdfView: YabrPDFView?
    private weak var delegate: ReaderEngineDelegate?
    private var bookId: String
    
    private var activeHighlights = [UUID: ReaderEngineHighlight]()

    init(pdfView: YabrPDFView, delegate: ReaderEngineDelegate?, bookId: String) {
        self.pdfView = pdfView
        self.delegate = delegate
        self.bookId = bookId
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
        
        let uuid = UUID()
        let posData = try? JSONEncoder().encode(pdfHighlightPageLocations)
        let posString = posData != nil ? String(data: posData!, encoding: .utf8) : nil
        
        let engineHighlight = ReaderEngineHighlight(
            id: uuid.uuidString,
            bookId: bookId,
            readerName: "YabrPDF",
            page: pdfHighlightPageLocations.first?.page ?? 1,
            date: Date(),
            type: style,
            content: selection.string ?? "No Content",
            cfiStart: "/\((pdfHighlightPageLocations.first?.page ?? 1) * 2)",
            cfiEnd: "/\((pdfHighlightPageLocations.last?.page ?? 1) * 2)",
            ranges: posString
        )
        
        activeHighlights[uuid] = engineHighlight
        delegate?.readerEngine(pdfView, didAddHighlight: engineHighlight)
        
        let pdfHighlight = PDFHighlight(
            uuid: uuid,
            pos: pdfHighlightPageLocations,
            type: style,
            content: selection.string ?? "No Content",
            date: Date()
        )
        pdfView.injectHighlight(highlight: pdfHighlight)
    }

    func removeHighlight(uuid: UUID) {
        guard let pdfView = pdfView else { return }
        
        delegate?.readerEngine(pdfView, didRemoveHighlight: uuid.uuidString)
        
        if let engineHighlight = activeHighlights.removeValue(forKey: uuid),
           let pdfHighlight = convertToPDFHighlight(engineHighlight) {
            pdfView.removeHighlight(highlight: pdfHighlight)
        }
    }

    func modifyHighlightStyle(uuid: UUID, type: BookHighlightStyle) {
        guard let pdfView = pdfView,
              var engineHighlight = activeHighlights[uuid]
        else { return }
        
        if let oldPdfHighlight = convertToPDFHighlight(engineHighlight) {
            pdfView.removeHighlight(highlight: oldPdfHighlight)
        }
        
        engineHighlight.type = type.rawValue
        engineHighlight.date = Date()
        activeHighlights[uuid] = engineHighlight
        
        delegate?.readerEngine(pdfView, didAddHighlight: engineHighlight)
        
        if let newPdfHighlight = convertToPDFHighlight(engineHighlight) {
            pdfView.injectHighlight(highlight: newPdfHighlight)
        }
    }

    func applyHighlights(_ highlights: [ReaderEngineHighlight]) {
        guard let pdfView = pdfView else { return }
        
        activeHighlights.values.forEach { engineHighlight in
            if let pdfHighlight = convertToPDFHighlight(engineHighlight) {
                pdfView.removeHighlight(highlight: pdfHighlight)
            }
        }
        activeHighlights.removeAll()
        
        highlights.forEach { engineHighlight in
            guard let uuid = UUID(uuidString: engineHighlight.id) else { return }
            activeHighlights[uuid] = engineHighlight
            if let pdfHighlight = convertToPDFHighlight(engineHighlight) {
                pdfView.injectHighlight(highlight: pdfHighlight)
            }
        }
    }
    
    func injectAllHighlights() {
        guard let pdfView = pdfView else { return }
        activeHighlights.values.forEach { engineHighlight in
            if let pdfHighlight = convertToPDFHighlight(engineHighlight) {
                pdfView.injectHighlight(highlight: pdfHighlight)
            }
        }
    }
    
    private func convertToPDFHighlight(_ engineHighlight: ReaderEngineHighlight) -> PDFHighlight? {
        guard let uuid = UUID(uuidString: engineHighlight.id),
              let posData = engineHighlight.ranges?.data(using: .utf8),
              let pos = try? JSONDecoder().decode([PDFHighlight.PageLocation].self, from: posData)
        else { return nil }
        
        return PDFHighlight(uuid: uuid, pos: pos, type: engineHighlight.type, content: engineHighlight.content, note: engineHighlight.note, date: engineHighlight.date)
    }
}
