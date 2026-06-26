//
//  YabrPDFViewController+Navigation.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(macCatalyst 14.0, *)
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

                        if dest.page?.pageRef?.pageNumber != self.pdfView.currentPage?.pageRef?.pageNumber {
                            self.addBlankSubView(page: dest.page)
                        }
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
            if curPage.pageRef?.pageNumber != self.pdfView.currentPage?.pageRef?.pageNumber {
                self.addBlankSubView(page: curPage)
            }
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

        addBlankSubView(page: curPage)

        [PDFDisplayBox.mediaBox, PDFDisplayBox.cropBox, PDFDisplayBox.trimBox, PDFDisplayBox.bleedBox, PDFDisplayBox.artBox].forEach {
            let bounds = curPage.bounds(for: $0)
            print("\(#function) boundsForBox box=\($0.rawValue) bounds=\(bounds)")
        }
        let boundsForCropBox = curPage.bounds(for: .cropBox)
        let boundsForMediaBox = curPage.bounds(for: .mediaBox)
        let boundForVisibleContentKey = PageVisibleContentKey(
            pageNumber: curPageNum,
            readingDirection: pdfOptions.readingDirection,
            hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
            vMarginDetectStrength: pdfOptions.vMarginDetectStrength
        )

        let boundForVisibleContent = marginCropController.visibleBounds(
            for: curPage,
            key: boundForVisibleContentKey,
            marginOffset: pdfOptions.marginOffset
        )

        marginCropController.preAnalyzeAdjacentPages(
            currentPageNumber: curPageNum,
            document: pdfView.document,
            readingDirection: pdfOptions.readingDirection,
            hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
            vMarginDetectStrength: pdfOptions.vMarginDetectStrength,
            marginOffset: pdfOptions.marginOffset
        )
        print("\(#function) pageVisibleContentBounds.count=\(marginCropController.visibleContentBounds.count)")

        if let pageViewPosition = getPageViewPositionHistory(curPageNum),
           pageViewPosition.scaler > 0,
           pageViewPosition.viewSize == pdfView.frame.size {
            let lastDest = PDFDestination(
                page: curPage,
                at: pageViewPosition.point
            )
            lastDest.zoom = pageViewPosition.scaler
            print("\(#function) displayMode=\(pdfView.displayMode) BEFORE POINT lastDestPoint=\(lastDest.point)")

            let bottomRight = PDFDestination(
                page: curPage,
                at: CGPoint(x: lastDest.point.x + boundsForCropBox.width, y: lastDest.point.y + boundsForCropBox.height)
            )
            bottomRight.zoom = 1.0

            pdfView.scaleFactor = pageViewPosition.scaler

            pdfView.go(to: bottomRight)
            pdfView.go(to: lastDest)
            return
        }

        guard pdfView.scaleFactor > 0 else { return }

        let visibleWidthRatio = 1.0 * (boundForVisibleContent.width + 1) / boundsForCropBox.width
        let visibleHeightRatio = 1.0 * (boundForVisibleContent.height + 1) / boundsForCropBox.height
        print("\(#function) curScale scaleFactor=\(pdfView.scaleFactor) visibleWidthRatio=\(visibleWidthRatio) visibleHeightRatio=\(visibleHeightRatio) boundsForCropBox=\(boundsForCropBox) boundForVisibleContent=\(boundForVisibleContent)")

        let newDestX = boundForVisibleContent.minX + boundsForMediaBox.minX + 2
        let newDestY = boundsForCropBox.height - boundForVisibleContent.minY + 2

        let visibleRectInView = pdfView.convert(
            CGRect(
                x: newDestX,
                y: newDestY,
                width: boundsForCropBox.width * visibleWidthRatio,
                height: boundsForCropBox.height * visibleHeightRatio
            ),
            from: curPage
        )

        print("\(#function) pdfView pdfView.frame=\(pdfView.frame)")
        print("\(#function) initialRect visibleRectInView=\(visibleRectInView)")

        let insetsHorizontalScaleFactor = 1.0 - (pdfOptions.hMarginAutoScaler * 2.0) / 100.0
        let insetsVerticalScaleFactor = 1.0 - (pdfOptions.vMarginAutoScaler * 2.0) / 100.0
        let scaleFactor = { () -> CGFloat in
            if pdfOptions.lastScale < 0 || pdfOptions.selectedAutoScaler != PDFAutoScaler.Custom {
                switch pdfOptions.selectedAutoScaler {
                case .Width:
                    return pdfView.scaleFactor * pdfView.frame.width / visibleRectInView.width * CGFloat(insetsHorizontalScaleFactor)
                case .Height:
                    return pdfView.scaleFactor * pdfView.frame.height / visibleRectInView.height * CGFloat(insetsVerticalScaleFactor)
                default:
                    return min(
                        pdfView.scaleFactor * pdfView.frame.width / visibleRectInView.width * CGFloat(insetsHorizontalScaleFactor),
                        pdfView.scaleFactor * pdfView.frame.height / visibleRectInView.height * CGFloat(insetsVerticalScaleFactor)
                    )
                }
            } else {
                return pdfOptions.lastScale
            }
        }()
        pdfView.scaleFactor = scaleFactor

        let viewFrameInPDF = pdfView.convert(pdfView.frame, to: curPage)

        var newDestPoint = CGPoint(
            x: newDestX - (1.0 - insetsHorizontalScaleFactor) / 2 * boundsForCropBox.width + boundsForCropBox.minX,
            y: newDestY + boundsForCropBox.minY + (1.0 - insetsVerticalScaleFactor) / 2 * viewFrameInPDF.height
        )

        if let pageViewPositionHistory = getPageViewPositionHistory(curPageNum) {
            if pageViewPositionHistory.point.x.isNaN == false {
                newDestPoint.x = pageViewPositionHistory.point.x
            }
            if pageViewPositionHistory.point.y.isNaN == false {
                newDestPoint.y = pageViewPositionHistory.point.y
            }
            print("\(#function) newDest newDestX=\(newDestX) minus=\((1.0 - insetsHorizontalScaleFactor) / 2 * boundsForCropBox.width) plus=\(boundsForCropBox.minX) history=\(pageViewPositionHistory.point.x)")
            print("\(#function) newDest newDestY=\(newDestX) plus1=\(0) plus2=\(boundsForCropBox.minY) plus3=\((1.0 - insetsVerticalScaleFactor) / 2 * viewFrameInPDF.height) history=\(pageViewPositionHistory.point.y)")
        } else {
            print("\(#function) newDest newDestX=\(newDestX) minus=\((1.0 - insetsHorizontalScaleFactor) / 2 * boundsForCropBox.width) plus=\(boundsForCropBox.minX)")
            print("\(#function) newDest newDestY=\(newDestX) plus1=\(0) plus2=\(boundsForCropBox.minY) plus3=\((1.0 - insetsVerticalScaleFactor) / 2 * viewFrameInPDF.height)")
        }

        let newDest = PDFDestination(page: curPage, at: newDestPoint)
        let initialDestPoint = pdfView.currentDestination!.point

        print("\(#function) BEFORE POINT curDestPoint=\(pdfView.currentDestination!.point) newDestPoint=\(newDest.point) boundsForCropBox=\(boundsForCropBox)")

        let bottomRight = PDFDestination(
            page: curPage,
            at: CGPoint(x: boundsForMediaBox.width, y: 0)
        )

        pdfView.go(to: bottomRight)
        print("\(#function) BEFORE POINT BOTTOM RIGHT curDestPoint=\(pdfView.currentDestination!.point) newDestPoint=\(newDest.point) boundsForCropBox=\(boundsForCropBox)")

        pdfView.go(to: newDest)

        var afterPointX = pdfView.currentDestination!.point.x
        var afterPointY = pdfView.currentDestination!.point.y + viewFrameInPDF.height

        print("\(#function) AFTER POINT scale=\(scaleFactor) curDestPoint=\(pdfView.currentDestination!.point) curDestPointInPDF=\(afterPointX),\(afterPointY) gotoDestPoint=\(newDest.point) boundsForCropBox=\(boundsForCropBox)")

        let newDestForCompensation = PDFDestination(
            page: curPage,
            at: CGPoint(
                x: newDest.point.x - (afterPointX - newDest.point.x),
                y: newDest.point.y - (afterPointY - newDest.point.y) - (initialDestPoint.y < 0 ? initialDestPoint.y : 0)
            )
        )

        pdfView.go(to: bottomRight)
        pdfView.go(to: newDestForCompensation)
        afterPointX = pdfView.currentDestination!.point.x
        afterPointY = pdfView.currentDestination!.point.y + viewFrameInPDF.height
        print("\(#function) AFTER POINT COMPENSATION scale=\(scaleFactor) curDestPoint=\(pdfView.currentDestination!.point) curDestPointInPDF=\(afterPointX),\(afterPointY) gotoDestPoint=\(newDestForCompensation.point) boundsForCropBox=\(boundsForCropBox)")
        print("\(#function) scaleFactor=\(pdfOptions.lastScale)")

        #if DEBUG
        let newDestAnnotation = PDFAnnotation(
            bounds: .init(origin: newDest.point, size: .init(width: 4, height: 4)),
            forType: .circle,
            withProperties: nil
        )
        curPage.addAnnotation(newDestAnnotation)

        let newDestForCompensationAnnotation = PDFAnnotation(
            bounds: .init(origin: newDestForCompensation.point, size: .init(width: 4, height: 4)),
            forType: .square,
            withProperties: nil
        )
        newDestForCompensationAnnotation.color = .red
        curPage.addAnnotation(newDestForCompensationAnnotation)

        print("\(#function) newDestPoint=\(newDest.point) cropBox=\(curPage.bounds(for: .cropBox)) mediaBox=\(curPage.bounds(for: .mediaBox))")
        #endif

        updatePageViewPositionHistory()
        updateReadingProgress()
    }

    @objc func finishReading(sender: UIBarButtonItem) {
        updatePageViewPositionHistory()
        updateReadingProgress()

        self.dismiss(animated: true) {
            self.pdfView.document = nil
            self.yabrPDFMetaSource = nil
            self.tocList.removeAll()
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
        guard let curDest = pdfView.currentDestination,
              let curDestPage = curDest.page,
              let curPage = pdfView.page(for: .zero, nearest: true),
              let curPageNum = curPage.pageRef?.pageNumber
        else { return nil }

        var curDestPoint = curDest.point
        if curPage != curDestPage {
            let curDestPointInView = pdfView.convert(curDestPoint, from: curDestPage)
            let curDestPointInCurPage = pdfView.convert(curDestPointInView, to: curPage)
            curDestPoint = curDestPointInCurPage
        }

        let viewFrameInPDF = pdfView.convert(pdfView.frame, to: curPage)

        let pointUpperLeft = CGPoint(
            x: curDestPoint.x,
            y: curDestPoint.y + viewFrameInPDF.height
        )

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
