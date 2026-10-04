//
//  YabrPDFViewController+Options.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    func handleOptionsChange(pdfOptions: PDFPreferenceValue) {
        let oldOptions = self.pdfOptions
        // Under the old options: the region on screen of a split page (#97).
        let region = readingRegionOnScreen()
        self.pdfOptions = pdfOptions

        if oldOptions.pageMode != self.pdfOptions.pageMode || oldOptions.scrollDirection != self.pdfOptions.scrollDirection {
            updatePageViewPositionHistory()
        }

        // Light tints are an overlay; only the dark theme is drawn into page tiles,
        // which need re-rendering when it toggles.
        if oldOptions.themePalette.drawsInverted != self.pdfOptions.themePalette.drawsInverted {
            invalidateRenderedPages()
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
        // The same regions under the new options: stay on the region on screen.
        if let region,
           oldOptions.spreadMode == self.pdfOptions.spreadMode,
           oldOptions.columnsMode == self.pdfOptions.columnsMode,
           oldOptions.readingDirection == self.pdfOptions.readingDirection {
            readingFlow.setPendingTarget(.region(region.region), pageNumber: region.pageNumber)
        }
        handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
    }

    /// Forces PDFKit to redraw its cached page tiles (the dark theme is drawn into
    /// them). Neither `annotationsChanged(on:)` nor a scale round-trip invalidates
    /// the cache, so the document is re-attached and the position restored from
    /// history, under the jump mask.
    func invalidateRenderedPages() {
        guard let document = pdfView.document,
              let page = pdfView.currentPage
        else { return }

        updatePageViewPositionHistory()
        // Cover with the page already rendered in the new theme before PDFKit
        // drops its tiles; the restored viewport is identical.
        surface.showJumpMask(for: page)
        // Buffers hold tiles of the old theme; refilled after the page change.
        surface.discardBuffers()
        isReattachingDocument = true
        pdfView.document = nil
        pdfView.document = document
        isReattachingDocument = false
        pdfView.go(to: page)
        if pdfViewAux.document === document {
            pdfViewAux.document = nil
            pdfViewAux.document = document
        }
    }

    func handleAutoScalerChange(autoScaler: PDFAutoScaler, hMarginAutoScaler: Double, vMarginAutoScaler: Double) {

    }

    @objc func handleScaleChange(_ sender: Any?) {
        let newScale = pdfView.scaleFactor
        guard abs(pdfOptions.lastScale - newScale) > 0.0001 else { return }

        isRecordingScale = true
        pdfOptions.lastScale = newScale
        isRecordingScale = false
        print("handleScaleChange: \(pdfOptions.lastScale)")
    }

    @objc func handleDisplayBoxChange(_ sender: Any?) {
        print("handleDisplayBoxChange: \(String(describing: self.pdfView.currentDestination))")
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
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
