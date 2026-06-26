//
//  PDFSearchController.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

class PDFSearchController: NSObject {
    private weak var pdfView: YabrPDFView?
    private var yabrPDFMetaSource: YabrPDFMetaSource?

    init(pdfView: YabrPDFView, metaSource: YabrPDFMetaSource?) {
        self.pdfView = pdfView
        self.yabrPDFMetaSource = metaSource
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
