//
//  PDFViewUIVC.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import SwiftUI
import PDFKit

@available(macCatalyst 14.0, *)
struct PDFViewUI: UIViewControllerRepresentable {
    let pdfViewContainer = PDFViewContainer()
    
    func makeUIViewController(context: Context) -> PDFViewContainer {
        return pdfViewContainer
    }
    
    func open(pdfURL: URL, bookDetailView: BookDetailView) {
        //pdfView.document = PDFDocument(url: pdfURL)
        pdfViewContainer.open(pdfURL: pdfURL, bookDetailView: bookDetailView)
    }
    
    func updateUIViewController(_ uiView: PDFViewContainer, context: Context) {

    }
}
