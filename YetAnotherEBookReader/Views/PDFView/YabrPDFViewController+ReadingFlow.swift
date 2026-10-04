//
//  YabrPDFViewController+ReadingFlow.swift
//  YetAnotherEBookReader
//
//  Reading a page in steps (#97): a page turn first steps through the page's
//  regions, a screen at a time where a region is longer than the view, and only
//  then changes page. A page read whole is one region, so a page longer than
//  the view is read a screen at a time too.
//

import PDFKit
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    /// How `page` is read in `view` in single-page mode: region by region when it
    /// is split, else a screen at a time when it is longer than the view. Nil
    /// when it is shown in one step (it fits) or in Scroll mode.
    func readingPlan(for page: PDFPage, in view: YabrPDFView) -> PDFPageReadingPlan? {
        guard pdfOptions.pageMode == .Page,
              view.bounds.width > 1,
              view.bounds.height > 1
        else { return nil }
        let key = PageVisibleContentKey(pageNumber: page.pageRef?.pageNumber ?? 1, options: pdfOptions)
        let layout = marginCropController.readingLayout(for: page, key: key)

        let cropBox = page.bounds(for: .cropBox)
        let display = PDFPageDisplaySpace(box: cropBox, rotation: page.rotation)
        let pageBounds = CGRect(origin: .zero, size: display.size)
        let readableRect = view.bounds.inset(by: pageLayoutInsets)
        // Whole: the content box the page is fitted to.
        let regions = layout.readsWhole ? [layout.bounds] : layout.regions.map(\.rect)
        let plan = PDFPageReadingPlan(
            regions: regions.map {
                display.toDisplay(PDFPageViewportFitter.pageSpaceRect(detected: $0, pageBounds: cropBox))
            },
            display: display
        ) { region in
            viewportFitInput(content: region, pageBounds: pageBounds, readableRect: readableRect)
        }
        return plan.steps.count > 1 ? plan : nil
    }

    /// The fitter's input for `content` (display space) under the current options.
    func viewportFitInput(content: CGRect, pageBounds: CGRect, readableRect: CGRect) -> PDFPageViewportFitter.Input {
        PDFPageViewportFitter.Input(
            contentBounds: content,
            pageBounds: pageBounds,
            readableRect: readableRect,
            autoScaler: pdfOptions.selectedAutoScaler,
            hMarginPercent: pdfOptions.hMarginAutoScaler,
            vMarginPercent: pdfOptions.vMarginAutoScaler,
            customScale: pdfOptions.lastScale,
            readingDirection: pdfOptions.readingDirection,
            marginOffsetPercent: pdfOptions.marginOffset
        )
    }

    /// The viewport a page read in steps lands on: the turn's target, an exact
    /// saved position, the step nearest a saved point, or its first step.
    func plannedPageViewport(
        _ plan: PDFPageReadingPlan,
        history: PageViewPosition?,
        target: PDFReadingTarget?,
        in view: YabrPDFView
    ) -> (fit: PDFPageViewportFit, restoresSavedPosition: Bool) {
        switch target {
        case .first:
            return (plan.pageFit(at: 0), false)
        case .last:
            return (plan.pageFit(at: plan.steps.count - 1), false)
        case .region(let region):
            guard let history else { return (plan.pageFit(at: plan.stepIndex(region: region)), false) }
            let step = plan.stepIndex(nearestUpperLeft: history.point, scale: history.scaler, viewBounds: view.bounds, region: region)
            return (plan.pageFit(at: step), false)
        case nil:
            break
        }
        guard let history else { return (plan.pageFit(at: 0), false) }
        if history.scaler > 0,
           history.viewSize == view.frame.size,
           !history.point.x.isNaN,
           !history.point.y.isNaN {
            return (PDFPageViewportFitter.restore(scale: history.scaler, upperLeft: history.point, viewBounds: view.bounds), true)
        }
        let step = plan.stepIndex(nearestUpperLeft: history.point, scale: history.scaler, viewBounds: view.bounds)
        return (plan.pageFit(at: step), false)
    }

    /// The step of `plan` the page view shows now, from the page point at its
    /// top-left corner and its scale: a drag or a zoom since the last step counts.
    func currentStep(in plan: PDFPageReadingPlan, of page: PDFPage) -> Int {
        let upperLeft = pdfView.convert(CGPoint(x: pdfView.bounds.minX, y: pdfView.bounds.minY), to: page)
        return plan.stepIndex(nearestUpperLeft: upperLeft, scale: pdfView.scaleFactor, viewBounds: pdfView.bounds)
    }

    /// Moves to the next (`forward`) or previous step of the page on screen. False
    /// at its first or last step, or when it is shown in one step: the page turns.
    func stepWithinPage(forward: Bool) -> Bool {
        guard pdfView.displayMode == .singlePage,
              let page = pdfView.currentPage,
              let plan = readingPlan(for: page, in: pdfView)
        else { return false }
        let step = currentStep(in: plan, of: page) + (forward ? 1 : -1)
        guard plan.steps.indices.contains(step) else { return false }

        menuManager.dismissHighlightMenu()
        pdfView.clearSelection()
        pdfView.applyViewport(plan.pageFit(at: step), on: page)
        // PDFKit shows the newly visible part at low resolution until its tiles
        // render; the mask draws it at the new viewport meanwhile.
        surface.showJumpMask(for: page)
        updatePageViewPositionHistory()
        updateReadingProgress()
        return true
    }

    /// The page and region on screen, for keeping the region through a change
    /// that refits the page (a rotation, an options change): pass it to
    /// `readingFlow.setPendingTarget` before the page change that refits.
    func readingRegionOnScreen() -> (pageNumber: Int, region: Int)? {
        guard pdfView.displayMode == .singlePage,
              let page = pdfView.currentPage,
              let pageNumber = page.pageRef?.pageNumber,
              let plan = readingPlan(for: page, in: pdfView)
        else { return nil }
        return (pageNumber, plan.steps[currentStep(in: plan, of: page)].region)
    }
}
