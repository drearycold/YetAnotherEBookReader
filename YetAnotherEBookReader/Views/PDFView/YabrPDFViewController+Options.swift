//
//  YabrPDFViewController+Options.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(macCatalyst 14.0, *)
extension YabrPDFViewController {
    func handleOptionsChange(pdfOptions: PDFPreferenceValue) {
        let oldOptions = self.pdfOptions
        self.pdfOptions = pdfOptions

        if oldOptions.pageMode != self.pdfOptions.pageMode || oldOptions.scrollDirection != self.pdfOptions.scrollDirection {
            updatePageViewPositionHistory()
        }

        if oldOptions.themeMode != self.pdfOptions.themeMode {
//                self.pdfView.layoutDocumentView()
            //self.pdfView.invalidateIntrinsicContentSize()
            let scaleFactor = self.pdfView.scaleFactor
            self.pdfView.scaleFactor = 1.0
            self.pdfView.scaleFactor = scaleFactor
        }
        if let pageNum = pdfView.currentPage?.pageRef?.pageNumber {
            self.pageViewPositionHistory[pageNum]?.scaler = 0
            switch self.pdfOptions.readingDirection {
            case .LtR_TtB:
                self.pageViewPositionHistory[pageNum]?.point.x = .nan
            case .TtB_RtL:
                self.pageViewPositionHistory[pageNum]?.point.y = .nan
            }
        }
        handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
    }

    func handleAutoScalerChange(autoScaler: PDFAutoScaler, hMarginAutoScaler: Double, vMarginAutoScaler: Double) {

    }

    @objc func handleScaleChange(_ sender: Any?) {
        let newScale = pdfView.scaleFactor
        guard abs(pdfOptions.lastScale - newScale) > 0.0001 else { return }

        pdfOptions.lastScale = newScale
        print("handleScaleChange: \(pdfOptions.lastScale)")
    }

    @objc func handleDisplayBoxChange(_ sender: Any?) {
        print("handleDisplayBoxChange: \(self.pdfView.currentDestination!)")
    }
}

@available(macCatalyst 14.0, *)
extension YabrPDFViewController: ReaderEngineController {
    func applyPreferences(_ preferences: ReaderEnginePreferences) {
        var newOptions = pdfOptions
        newOptions.apply(preferences)

        self.handleOptionsChange(pdfOptions: newOptions)
    }

    func applyHighlights(_ highlights: [ReaderEngineHighlight]) {
        self.annotationManager.applyHighlights(highlights)
    }
}
