//
//  YabrPDFViewController+Navigation.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    func buildTocList() {
        DispatchQueue.global(qos: .utility).async {
            var tableOfContents = [UIMenuElement]()

            if let pdfDoc = self.pdfView.document, var outlineRoot = pdfDoc.outlineRoot {
                while outlineRoot.numberOfChildren == 1 {
                    outlineRoot = outlineRoot.child(at: 0)!
                }
                for i in (0..<outlineRoot.numberOfChildren) {
                    self.tocList.append((outlineRoot.child(at: i)?.label ?? "Label at \(i)", outlineRoot.child(at: i)?.destination?.page?.pageRef?.pageNumber ?? 1))
                    tableOfContents.append(UIAction(title: outlineRoot.child(at: i)?.label ?? "Label at \(i)") { _ in
                        guard let dest = outlineRoot.child(at: i)?.destination,
                              let curPage = self.pdfView.currentPage
                        else { return }

                        self.updateHistoryMenu(curPage: curPage)

                        self.markJumpTarget(dest.page)
                        self.pdfView.go(to: dest)
                    })

                }
            }

            let navContentsMenu = UIMenu(title: "Contents", children: tableOfContents)

            DispatchQueue.main.async {
                self.titleInfoButton.menu = navContentsMenu
            }
        }
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
        let showsJumpMask = pendingJumpMaskPage == curPageNum || pdfOptions.themePalette.drawsInverted
        pendingJumpMaskPage = nil
        pageIndicator.setTitle("\(curPageNum) / \(pdfView.document?.pageCount ?? 1)", for: .normal)
        pageSlider.setValue(Float(curPageNum), animated: true)

        print("\(#function) curPageNum=\(curPageNum) pageIndicator=\(pageIndicator.title(for: .normal) ?? "Untitled") pageSlider=\(pageSlider.value)")

        guard pdfView.frame.width > 1.0 else { return }

        if pdfView.displayMode != .singlePage {
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

        let boundForVisibleContentKey = PageVisibleContentKey(
            pageNumber: curPageNum,
            readingDirection: pdfOptions.readingDirection,
            hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
            vMarginDetectStrength: pdfOptions.vMarginDetectStrength
        )
        let boundForVisibleContent = marginCropController.visibleBounds(for: curPage, key: boundForVisibleContentKey)

        marginCropController.preAnalyzeAdjacentPages(
            currentPageNumber: curPageNum,
            document: pdfView.document,
            readingDirection: pdfOptions.readingDirection,
            hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
            vMarginDetectStrength: pdfOptions.vMarginDetectStrength
        )

        let pageHistory = getPageViewPositionHistory(curPageNum)
        if let pageViewPosition = pageHistory,
           pageViewPosition.scaler > 0,
           pageViewPosition.viewSize == pdfView.frame.size,
           !pageViewPosition.point.x.isNaN,
           !pageViewPosition.point.y.isNaN {
            pdfView.applyViewport(
                PDFPageViewportFitter.restore(
                    scale: pageViewPosition.scaler,
                    upperLeft: pageViewPosition.point,
                    viewBounds: pdfView.bounds
                ),
                on: curPage
            )
            if showsJumpMask {
                pdfView.showJumpMask(for: curPage)
            }
            return
        }

        let boundsForCropBox = curPage.bounds(for: .cropBox)
        var fit = PDFPageViewportFitter.fit(
            PDFPageViewportFitter.Input(
                contentBounds: PDFPageViewportFitter.pageSpaceRect(detected: boundForVisibleContent, pageBounds: boundsForCropBox),
                pageBounds: boundsForCropBox,
                readableRect: pdfView.bounds.inset(by: pdfView.safeAreaInsets),
                autoScaler: pdfOptions.selectedAutoScaler,
                hMarginPercent: pdfOptions.hMarginAutoScaler,
                vMarginPercent: pdfOptions.vMarginAutoScaler,
                customScale: pdfOptions.lastScale,
                readingDirection: pdfOptions.readingDirection,
                marginOffsetPercent: pdfOptions.marginOffset
            )
        )

        // Keep the axis the reader already positioned (saved position, rotation, or
        // an options change that only reset the other axis).
        if let pageHistory {
            if !pageHistory.point.x.isNaN {
                fit.pageAnchor.x = pageHistory.point.x
                fit.viewAnchor.x = pdfView.bounds.minX
            }
            if !pageHistory.point.y.isNaN {
                fit.pageAnchor.y = pageHistory.point.y
                fit.viewAnchor.y = pdfView.bounds.minY
            }
        }

        pdfView.applyViewport(fit, on: curPage)
        if showsJumpMask {
            pdfView.showJumpMask(for: curPage)
        }

        updatePageViewPositionHistory()
        updateReadingProgress()
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
