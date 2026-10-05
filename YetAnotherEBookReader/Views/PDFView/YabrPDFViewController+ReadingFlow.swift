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
        case .destination(let focus):
            let step = plan.stepIndex(showing: focus, readableRect: view.bounds.inset(by: pageLayoutInsets))
            return (plan.pageFit(at: step), false)
        case .lowerLeft(let point):
            return (plan.pageFit(at: plan.stepIndex(nearestLowerLeft: point, viewBounds: view.bounds)), false)
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
        let scale = pdfView.scaleFactor
        let tilesBefore = surface.shownTiles(of: pdfView, page: page)
        pdfView.applyViewport(plan.pageFit(at: step), on: page)
        // PDFKit shows the newly visible part at low resolution until its tiles
        // render; the mask, prepared ahead, shows it at the new viewport
        // meanwhile. At another scale every tile is new.
        var newTiles = surface.shownTiles(of: pdfView, page: page)
        if abs(pdfView.scaleFactor - scale) < 0.0005 {
            newTiles.subtract(tilesBefore)
        }
        surface.showJumpMask(for: page, holdingFor: newTiles)
        updatePageViewPositionHistory()
        updateReadingProgress()
        updatePageIndicator()
        prepareStepMasks()
        return true
    }

    /// Draws the masks of the next and previous step of the page on screen in
    /// the background, when they are on this page (page turns have the buffers),
    /// so a step shows its mask at once.
    func prepareStepMasks() {
        guard pdfView.displayMode == .singlePage,
              let page = pdfView.currentPage,
              let plan = readingPlan(for: page, in: pdfView)
        else {
            surface.discardPreparedJumpMasks()
            return
        }
        let step = currentStep(in: plan, of: page)
        let layouts = [step + 1, step - 1]
            .filter(plan.steps.indices.contains)
            .map { plan.steps[$0].fit.pageToView(display: plan.display) }
        surface.prepareJumpMasks(of: page, layouts: layouts)
    }

    // MARK: Jumps

    /// Jumps to an outline or link destination: a page read in steps lands on
    /// the step showing its point.
    func jump(to destination: PDFDestination) {
        guard let page = destination.page else { return }
        // PDFKit marks an unspecified coordinate with a huge value.
        func specified(_ value: CGFloat) -> CGFloat { abs(value) < 1e30 ? value : .nan }
        let point = CGPoint(x: specified(destination.point.x), y: specified(destination.point.y))
        jump(to: page, target: .destination(CGRect(origin: point, size: .zero))) { $0.go(to: destination) }
    }

    /// Jumps to a search hit: the step showing it.
    func jump(to selection: PDFSelection) {
        guard let page = selection.pages.first else { return }
        jump(to: page, target: .destination(selection.bounds(for: page))) { $0.go(to: selection) }
    }

    /// Jumps to `rect` on `page` (a highlight): the step showing it.
    func jump(to page: PDFPage, showing rect: CGRect) {
        jump(to: page, target: .destination(rect)) { $0.go(to: page) }
    }

    /// Jumps to a bookmark, whose `point` is the `currentDestination` it saved:
    /// the step that showed it.
    func jump(toBookmarkOn page: PDFPage, at point: CGPoint) {
        jump(to: page, target: .lowerLeft(point)) { $0.go(to: PDFDestination(page: page, at: point)) }
    }

    /// Lands a jump on `page`'s step for `target` when it is read in steps;
    /// `go` is PDFKit's own jump, which places it in Scroll mode.
    private func jump(to page: PDFPage, target: PDFReadingTarget, go: (YabrPDFView) -> Void) {
        guard page === pdfView.currentPage else {
            if let pageNumber = page.pageRef?.pageNumber {
                readingFlow.setPendingTarget(target, pageNumber: pageNumber)
            }
            markJumpTarget(page)
            if pdfView.displayMode == .singlePage {
                // `handlePageChange` places the page. PDFKit's jump to a point or
                // a selection would scroll on after it, sideways.
                pdfView.go(to: page)
            } else {
                go(pdfView)
            }
            return
        }
        // On the page on screen there is no page change to land it; PDFKit
        // would place it its own way.
        guard pdfView.displayMode == .singlePage, let plan = readingPlan(for: page, in: pdfView) else {
            go(pdfView)
            return
        }
        menuManager.dismissHighlightMenu()
        pdfView.applyViewport(plannedPageViewport(plan, history: nil, target: target, in: pdfView).fit, on: page)
        surface.showJumpMask(for: page)
        updatePageViewPositionHistory()
        updateReadingProgress()
        updatePageIndicator()
        prepareStepMasks()
    }

    /// "12 / 300", and on a page read in steps the step on screen of its turns:
    /// "12 / 300 · 3/7".
    func updatePageIndicator() {
        guard let page = pdfView.currentPage else { return }
        var title = "\(page.pageRef?.pageNumber ?? 1) / \(pdfView.document?.pageCount ?? 1)"
        if pdfView.displayMode == .singlePage, let plan = readingPlan(for: page, in: pdfView) {
            title += " · \(currentStep(in: plan, of: page) + 1)/\(plan.steps.count)"
        }
        pageIndicator.setTitle(title, for: .normal)
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
