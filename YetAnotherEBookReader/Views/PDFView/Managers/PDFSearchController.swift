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
