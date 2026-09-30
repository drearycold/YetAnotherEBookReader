//
//  YabrPDFViewController+Navigation.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    /// Builds the Contents menu from the outline's top level. Cheap, so it runs on
    /// the main thread (it used to fill `tocList` from a background queue).
    func buildTocList() {
        var tableOfContents = [UIMenuElement]()
        tocList.removeAll()

        if let pdfDoc = pdfView.document, var outlineRoot = pdfDoc.outlineRoot {
            while outlineRoot.numberOfChildren == 1, let onlyChild = outlineRoot.child(at: 0) {
                outlineRoot = onlyChild
            }
            for i in 0..<outlineRoot.numberOfChildren {
                let item = outlineRoot.child(at: i)
                let label = item?.label ?? "Label at \(i)"
                tocList.append((label, item?.destination?.page?.pageRef?.pageNumber ?? 1))
                tableOfContents.append(UIAction(title: label) { [weak self] _ in
                    guard let self,
                          let dest = item?.destination,
                          let curPage = self.pdfView.currentPage
                    else { return }

                    self.updateHistoryMenu(curPage: curPage)

                    self.markJumpTarget(dest.page)
                    self.pdfView.go(to: dest)
                })
            }
        }

        titleInfoButton.menu = UIMenu(title: "Contents", children: tableOfContents)
    }

    func updateHistoryMenu(curPage: PDFPage, location: CGRect? = nil) {
        guard let pdfDoc = curPage.document else { return }

        var lastHistoryLabel = "Page \(curPage.pageRef!.pageNumber)"
        if let outlineRoot = pdfDoc.outlineRoot,
           let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)),
           let curPageSelectionText = curPageSelection.string,
           curPageSelectionText.count > 5,
           var curPageOutlineItem = pdfDoc.outlineItem(for: curPageSelection) {

            print("\(curPageSelectionText)")
            while curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot {
                curPageOutlineItem = curPageOutlineItem.parent!
            }
            lastHistoryLabel += " of \(curPageOutlineItem.label!)"
        }

        var historyItems = self.historyMenu.children
        historyItems.append(UIAction(title: lastHistoryLabel) { action in
            var children = self.historyMenu.children
            if let index = children.firstIndex(of: action) {
                children.removeLast(children.count - index)
                self.historyMenu = self.historyMenu.replacingChildren(children)
                let newMenu = self.navigationItem.rightBarButtonItems?.first?.menu?.replacingChildren(children)
                self.navigationItem.rightBarButtonItems?.first?.menu = nil  //MUST HAVE, otherwise no effect
                self.navigationItem.rightBarButtonItems?.first?.menu = newMenu
                if children.isEmpty {
                    self.navigationItem.rightBarButtonItems?.first?.isEnabled = false
                    self.pageBackButton.isHidden = true
                    self.pageBackButton.setTitle("", for: .normal)
                } else if let lastHistoryItem = children.last as? UIAction {
                    self.pageBackButton.isHidden = false
                    if lastHistoryItem.title.count > 20 {
                        self.pageBackButton.setAttributedTitle(
                            .init(
                                string: " Back to \(lastHistoryItem.title.prefix(20))...",
                                attributes: [
                                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12.0)
                                ]
                            ),
                            for: .normal
                        )
                    } else {
                        self.pageBackButton.setAttributedTitle(
                            .init(
                                string: " Back to \(lastHistoryItem.title)",
                                attributes: [
                                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12.0)
                                ]
                            ),
                            for: .normal
                        )
                    }
                }
            }
            self.markJumpTarget(curPage)
            if let location = location {
                self.pdfView.go(to: location, on: curPage)
            } else {
                self.pdfView.go(to: curPage)
            }
        })

        self.historyMenu = self.historyMenu.replacingChildren(historyItems)
        let newMenu = self.navigationItem.rightBarButtonItems?.first?.menu?.replacingChildren(historyItems)
        self.navigationItem.rightBarButtonItems?.first?.menu = nil  //MUST HAVE, otherwise no effect
        self.navigationItem.rightBarButtonItems?.first?.menu = newMenu
        self.navigationItem.rightBarButtonItems?.first?.isEnabled = true

        self.pageBackButton.isHidden = false
        if lastHistoryLabel.count > 20 {
            self.pageBackButton.setAttributedTitle(
                .init(
                    string: " Back to \(lastHistoryLabel.prefix(20))...",
                    attributes: [
                        NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12.0)
                    ]
                ),
                for: .normal
            )
        } else {
            self.pageBackButton.setAttributedTitle(
                .init(
                    string: " Back to \(lastHistoryLabel)",
                    attributes: [
                        NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12.0)
                    ]
                ),
                for: .normal
            )
        }
    }

    @objc func handlePageChange(notification: Notification) {
        // Re-attaching shows the first page for a moment.
        guard !isReattachingDocument else { return }
        var titleLabel = initialPosition?.chapterName
        guard let curPage = pdfView.currentPage else { return }

        if var outlineRoot = pdfView.document?.outlineRoot {
            while outlineRoot.numberOfChildren == 1 {
                outlineRoot = outlineRoot.child(at: 0)!
            }
            if let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)),
               !curPageSelection.selectionsByLine().isEmpty,
               var curPageOutlineItem = pdfView.document?.outlineItem(for: curPageSelection) {
                while curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot {
                    curPageOutlineItem = curPageOutlineItem.parent!
                }
                if curPageOutlineItem.label != nil && !curPageOutlineItem.label!.isEmpty {
                    titleLabel = curPageOutlineItem.label
                }
            }
        }
        self.titleInfoButton.setTitle(titleLabel, for: .normal)

        let curPageNum = pdfView.currentPage?.pageRef?.pageNumber ?? 1
        // Dark pages are drawn into PDFKit's tiles and a newly shown page is a
        // white placeholder until they render, so every dark page change is
        // covered; light themes only cover jumps.
        let isJumpTarget = pendingJumpMaskPage == curPageNum
        let showsJumpMask = isJumpTarget || pdfOptions.themePalette.drawsInverted
        pendingJumpMaskPage = nil
        pageIndicator.setTitle("\(curPageNum) / \(pdfView.document?.pageCount ?? 1)", for: .normal)
        pageSlider.setValue(Float(curPageNum), animated: true)

        print("\(#function) curPageNum=\(curPageNum) pageIndicator=\(pageIndicator.title(for: .normal) ?? "Untitled") pageSlider=\(pageSlider.value)")

        guard pdfView.frame.width > 1.0 else { return }

        if pdfView.displayMode != .singlePage {
            surface.discardBuffers()
            pdfView.restoreDefaultPageBreakMargins()
            pdfView.scaleFactor = pdfOptions.lastScale

            if let pageViewPosition = getPageViewPositionHistory(curPageNum),
               pageViewPosition.scaler > 0,
               pageViewPosition.viewSize == pdfView.frame.size || pageViewPosition.viewSize == .zero {
                let lastDest = PDFDestination(
                    page: curPage,
                    at: pageViewPosition.point
                )
                lastDest.zoom = pageViewPosition.scaler
                print("\(#function) displayMode=\(pdfView.displayMode) BEFORE POINT lastDestPoint=\(lastDest.point)")

                pdfView.scaleFactor = pageViewPosition.scaler

                pageViewPositionHistory.removeValue(forKey: curPageNum)
                pdfView.go(to: lastDest)
            }

            return
        }

        marginCropController.preAnalyzeAdjacentPages(
            currentPageNumber: curPageNum,
            document: pdfView.document,
            readingDirection: pdfOptions.readingDirection,
            hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
            vMarginDetectStrength: pdfOptions.vMarginDetectStrength,
            completion: { [weak self] in self?.refreshPageBuffers() }
        )

        let viewport = singlePageViewport(for: curPage, in: pdfView)
        pdfView.applyViewport(viewport.fit, on: curPage)
        // A buffered neighbour already rendered at this viewport hides PDFKit's
        // low-resolution placeholder while the page's tiles render; under dark it
        // also replaces the page-change mask (explicit jumps keep theirs).
        // A takeover already shows the page, fully rendered. Under dark only a
        // rendered buffer replaces the mask (an unrendered one shows PDFKit's
        // white placeholder).
        let takenOver = surface.consumeTakeover(of: curPage)
        let covered = !takenOver && surface.coverWithBuffer(showing: curPage)
        let coveredByRenderedBuffer = takenOver || (covered && surface.hasRenderedBuffer(showing: curPage))
        if isJumpTarget || (showsJumpMask && !coveredByRenderedBuffer) {
            surface.showJumpMask(for: curPage)
        }
        // A restored position is already in the history.
        if !viewport.restoresSavedPosition {
            updatePageViewPositionHistory()
        }
        updateReadingProgress()
    }

    /// The single-page viewport of `page` in `view`: its saved position, or a fit
    /// of its detected content that keeps any saved axis. Used for the page on
    /// screen and for the buffered neighbours, so both land identically.
    func singlePageViewport(for page: PDFPage, in view: YabrPDFView) -> (fit: PDFPageViewportFit, restoresSavedPosition: Bool) {
        let pageNumber = page.pageRef?.pageNumber ?? 1
        let pageHistory = getPageViewPositionHistory(pageNumber)
        if let pageViewPosition = pageHistory,
           pageViewPosition.scaler > 0,
           pageViewPosition.viewSize == view.frame.size,
           !pageViewPosition.point.x.isNaN,
           !pageViewPosition.point.y.isNaN {
            let fit = PDFPageViewportFitter.restore(
                scale: pageViewPosition.scaler,
                upperLeft: pageViewPosition.point,
                viewBounds: view.bounds
            )
            return (fit, true)
        }

        let key = PageVisibleContentKey(
            pageNumber: pageNumber,
            readingDirection: pdfOptions.readingDirection,
            hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
            vMarginDetectStrength: pdfOptions.vMarginDetectStrength
        )
        let boundForVisibleContent = marginCropController.visibleBounds(for: page, key: key)
        let boundsForCropBox = page.bounds(for: .cropBox)
        let contentBounds = PDFPageViewportFitter.pageSpaceRect(detected: boundForVisibleContent, pageBounds: boundsForCropBox)
        let readableRect = view.bounds.inset(by: view.safeAreaInsets)
        var fit = PDFPageViewportFitter.fit(
            PDFPageViewportFitter.Input(
                contentBounds: contentBounds,
                pageBounds: boundsForCropBox,
                readableRect: readableRect,
                autoScaler: pdfOptions.selectedAutoScaler,
                hMarginPercent: pdfOptions.hMarginAutoScaler,
                vMarginPercent: pdfOptions.vMarginAutoScaler,
                customScale: pdfOptions.lastScale,
                readingDirection: pdfOptions.readingDirection,
                marginOffsetPercent: pdfOptions.marginOffset
            )
        )

        // Keep the axis the reader already positioned (saved position, rotation, or
        // an options change that only reset the other axis), if the content still
        // needs scrolling along it. A saved top-left point is meaningless once the
        // content fits: after switching TtB_RtL from Width to Height it would put
        // the page at the left of the view.
        let fitted = contentBounds.width > 0 && contentBounds.height > 0 ? contentBounds : boundsForCropBox
        if let pageHistory {
            if !pageHistory.point.x.isNaN, fitted.width * fit.scale > readableRect.width + 0.5 {
                fit.pageAnchor.x = pageHistory.point.x
                fit.viewAnchor.x = view.bounds.minX
            }
            if !pageHistory.point.y.isNaN, fitted.height * fit.scale > readableRect.height + 0.5 {
                fit.pageAnchor.y = pageHistory.point.y
                fit.viewAnchor.y = view.bounds.minY
            }
        }
        return (fit, false)
    }

    /// Renders the neighbours of the page on screen in the surface's buffers
    /// (issues #54 / #55); single-page mode only.
    func refreshPageBuffers() {
        guard pdfView.displayMode == .singlePage,
              let document = pdfView.document,
              let page = pdfView.currentPage
        else {
            surface.discardBuffers()
            return
        }
        let index = document.index(for: page)
        // The next page first: reading forward is the common case.
        let neighbours = [index + 1, index - 1].compactMap { $0 >= 0 ? document.page(at: $0) : nil }
        surface.prepareBuffers(showing: neighbours) { [unowned self] page, view in
            singlePageViewport(for: page, in: view).fit
        }
    }

    func updateReadingProgress() {
        var position = [String: Any]()

        guard let curPageNum = pdfView.page(for: .zero, nearest: true)?.pageRef?.pageNumber,
              let curPagePos = getPageViewPositionHistory(curPageNum)
        else { return }

        position["pageNumber"] = curPageNum
        position["pageOffsetX"] = curPagePos.point.x
        position["pageOffsetY"] = curPagePos.point.y

        let bookProgress = 100.0 * Double(position["pageNumber"] as? Int ?? 0) / Double(pdfView.document?.pageCount ?? 1)

        var chapterProgress = 0.0
        let chapterName = titleInfoButton.currentTitle ?? "Unknown Title"
        if let firstIndex = tocList.lastIndex(where: { $0.0 == chapterName && $0.1 <= curPageNum }) {
            let curIndex = firstIndex.advanced(by: 0)
            let nextIndex = firstIndex.advanced(by: 1)
            let chapterStartPageNum = tocList[curIndex].1
            let chapterEndPageNum = nextIndex < tocList.count ?
                tocList[nextIndex].1 + 1 : (pdfView.document?.pageCount ?? 1) + 1
            if chapterEndPageNum > chapterStartPageNum {
                chapterProgress = 100.0 * Double(curPageNum - chapterStartPageNum) / Double(chapterEndPageNum - chapterStartPageNum)
            }
        }

        let enginePos = ReaderEnginePosition(
            pageNumber: curPageNum,
            maxPage: self.pdfView.document?.pageCount ?? 1,
            pageOffsetX: Int(curPagePos.point.x.rounded()),
            pageOffsetY: Int(curPagePos.point.y.rounded()),
            bookProgress: bookProgress,
            chapterProgress: chapterProgress,
            chapterName: chapterName,
            cfi: nil
        )
        self.readerEngineDelegate?.readerEngine(self, didUpdatePosition: enginePos)
    }

    func updatePageViewPositionHistory() {
        guard let pagePoint = getPagePoint() else { return }

        pageViewPositionHistory[pagePoint.0] = pagePoint.1
        print("updatePageViewPositionHistory \(pagePoint)")
    }

    func getPagePoint() -> (Int, PageViewPosition)? {
        guard let curPage = pdfView.page(for: .zero, nearest: true),
              let curPageNum = curPage.pageRef?.pageNumber
        else { return nil }

        // Measure the visible rect directly; same upper-left semantics as the
        // persisted pageOffsetX/Y.
        let visibleRect = pdfView.convert(pdfView.bounds, to: curPage)
        let pointUpperLeft = CGPoint(x: visibleRect.minX, y: visibleRect.maxY)

        return (
            curPageNum,
            PageViewPosition(
                scaler: pdfView.scaleFactor,
                point: pointUpperLeft,
                viewSize: pdfView.frame.size
            )
        )
    }

    func getPageViewPositionHistory(_ pageNum: Int) -> PageViewPosition? {
        return self.pageViewPositionHistory[pageNum]
    }
}
