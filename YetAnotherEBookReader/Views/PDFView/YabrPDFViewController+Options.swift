//
//  YabrPDFViewController+Options.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(macCatalyst 14.0, *)
extension YabrPDFViewController {
    func handleOptionsChange(pdfOptions: PDFOptions) {
        print(pdfOptions)

        let oldOptions = PDFOptions(value: self.pdfOptions)

        if self.pdfOptions !== pdfOptions {
            if let realm = self.pdfOptions.realm {
                try? realm.write {
                    self.pdfOptions.update(other: pdfOptions)
                }
            } else {
                self.pdfOptions = pdfOptions
                return
            }
        }

        if oldOptions.pageMode != self.pdfOptions.pageMode || oldOptions.scrollDirection != self.pdfOptions.scrollDirection {
            updatePageViewPositionHistory()
        }

        // Trigger didSet for UI refresh (colors, etc.)
        self.pdfOptions = self.pdfOptions

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

        if let realm = pdfOptions.realm {
            try? realm.write {
                pdfOptions.lastScale = newScale
            }
        } else {
            pdfOptions.lastScale = newScale
        }
        print("handleScaleChange: \(pdfOptions.lastScale)")
    }

    @objc func handleDisplayBoxChange(_ sender: Any?) {
        print("handleDisplayBoxChange: \(self.pdfView.currentDestination!)")
    }
}

@available(macCatalyst 14.0, *)
extension YabrPDFViewController: ReaderEngineController {
    func applyPreferences(_ preferences: ReaderEnginePreferences) {
        let newOptions = PDFOptions()
        switch preferences.themeMode {
        case 1:
            newOptions.themeMode = .serpia
        case 2:
            newOptions.themeMode = .dark
        default:
            newOptions.themeMode = .none
        }

        newOptions.pageMode = preferences.scroll ? .Scroll : .Page
        newOptions.scrollDirection = preferences.scrollDirection == 0 ? .Vertical : .Horizontal

        self.handleOptionsChange(pdfOptions: newOptions)
    }

    func applyHighlights(_ highlights: [ReaderEngineHighlight]) {
        self.annotationManager.applyHighlights(highlights)
    }
}
