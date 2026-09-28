//
//  YabrPDFViewController+Selection.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    /// Installs the edit menus (see `PDFMenuManager`) and preloads the dictionary.
    func configureSelectionMenus() {
        menuManager.install()
        yabrPDFMetaSource?.yabrPDFDictViewer(pdfView)?.1.loadViewIfNeeded()
    }

    func addHighlight(style: BookHighlightStyle) {
        guard let currentSelection = pdfView.currentSelection else { return }
        annotationManager.addHighlight(style: style.rawValue, selection: currentSelection)
    }

    @objc func dictViewerAction(_ sender: Any?) {
        guard let selectedText = pdfView.currentSelection?.string,
              let (_, dictViewer) = yabrPDFMetaSource?.yabrPDFDictViewer(pdfView) else { return }

        dictViewer.title = selectedText
        present(dictViewer, animated: true)
    }
}
