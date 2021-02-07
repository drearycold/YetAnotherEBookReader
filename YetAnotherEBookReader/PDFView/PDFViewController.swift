//
//  PDFViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import Foundation
import UIKit
import PDFKit
import OSLog


@available(macCatalyst 14.0, *)
class PDFViewController: UIViewController, PDFViewDelegate, PDFDocumentDelegate {
    var pdfView: PDFView?
    var bookDetailView: BookDetailView?
    var lastScale = CGFloat(1.0)
    
    let logger = Logger()
    
    var historyMenu = UIMenu(title: "History", children: [])
    
    var pageSlider = UISlider()
    var pageIndicator = UIButton()
    var pageNextButton = UIButton()
    var pagePrevButton = UIButton()
    
    let titleInfoButton = UIButton()
    
    let thumbImageView = UIImageView()
    let thumbController = UIViewController()
    
    var bookTitle: String!

    func open(pdfURL: URL, bookDetailView: BookDetailView) {
        self.bookDetailView = bookDetailView
        self.bookTitle = bookDetailView.book.title
        
        pdfView = PDFView()
        
        pdfView!.displayMode = PDFDisplayMode.singlePage
        pdfView!.displayDirection = PDFDisplayDirection.horizontal
        pdfView!.interpolationQuality = PDFInterpolationQuality.high
        
        pdfView!.usePageViewController(true, withViewOptions: nil)
        
//        setToolbarItems(
//            [   UIBarButtonItem.flexibleSpace(),
//                UIBarButtonItem(title: "0 / 0", style: .plain, target: self, action: nil),
//                UIBarButtonItem.flexibleSpace()
//            ], animated: true)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageChange(notification:)), name: .PDFViewPageChanged, object: pdfView!)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScaleChange(_:)), name: .PDFViewScaleChanged, object: nil)
        
        logger.info("pdfURL: \(pdfURL.absoluteString)")
        logger.info("Exist: \(FileManager.default.fileExists(atPath: pdfURL.path))")
        
        let pdfDoc = PDFDocument(url: pdfURL)
        pdfDoc?.delegate = self
        logger.info("pdfDoc: \(pdfDoc?.majorVersion ?? -1) \(pdfDoc?.minorVersion ?? -1)")
        
        pdfView!.document = pdfDoc
        pdfView!.autoScales = true

        pageIndicator.setTitle("0 / 0", for: .normal)
        pageIndicator.setTitleColor(.label, for: .normal)
        pageIndicator.addAction(UIAction(handler: { (action) in
            self.present(self.thumbController, animated: true, completion: nil)
        }), for: .primaryActionTriggered)
        
        pageSlider.minimumValue = 1
        pageSlider.maximumValue = Float(pdfView!.document!.pageCount)
        //pageSlider.frame = CGRect(x:0, y:0, width: 200, height: 40);
        pageSlider.isContinuous = true
        pageSlider.addAction(UIAction(handler: { (action) in
            if let destPage = self.pdfView!.document!.page(at: Int(self.pageSlider.value.rounded())) {
                self.pdfView!.go(to: destPage)
            }
        }), for: .valueChanged)

        pagePrevButton.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        pagePrevButton.addAction(UIAction(handler: { (action) in
            self.pdfView!.goToPreviousPage(self.pagePrevButton)
        }), for: .primaryActionTriggered)
        pageNextButton.setImage(UIImage(systemName: "arrow.right"), for: .normal)
        pageNextButton.addAction(UIAction(handler: { (action) in
            self.pdfView!.goToNextPage(self.pageNextButton)
        }), for: .primaryActionTriggered)
        
        
        var contents = [UIMenuElement]()
        
        if var outlineRoot = pdfDoc?.outlineRoot {
            while outlineRoot.numberOfChildren == 1 {
                outlineRoot = outlineRoot.child(at: 0)!
            }
            for i in (0..<outlineRoot.numberOfChildren) {
                contents.append(UIAction(title: outlineRoot.child(at: i)?.label ?? "Label at \(i)") { (action) in
                    if let dest = outlineRoot.child(at: i)?.destination {
                        if let curPage = self.pdfView?.currentPage {
//                            let backButton = UIBarButtonItem(title: " Back to \(curPage.pageRef!.pageNumber)", primaryAction: UIAction(handler: { (action) in
//                                self.pdfView!.go(to: curPage)
//                                var rightBarButtonItems = self.navigationItem.rightBarButtonItems!
//                                if rightBarButtonItems.count > 1 {
//                                    rightBarButtonItems.removeLast()
//                                    self.navigationItem.setRightBarButtonItems(rightBarButtonItems, animated: true)
//                                }
//                            }))
//                            var rightBarButtonItems = self.navigationItem.rightBarButtonItems!
//                            if rightBarButtonItems.count == 1 {
//                                rightBarButtonItems.append(backButton)
//                                self.navigationItem.setRightBarButtonItems(rightBarButtonItems, animated: true)
//                            }
                            
                            var historyItems = self.historyMenu.children
                            var lastHistoryLabel = "Page \(curPage.pageRef!.pageNumber)"
                            if let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)) {
                                if var curPageOutlineItem = pdfDoc?.outlineItem(for: curPageSelection) {
                                    while( curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot) {
                                        curPageOutlineItem = curPageOutlineItem.parent!
                                    }
                                    lastHistoryLabel += " of \(curPageOutlineItem.label!)"
                                }
                            }
                            historyItems.append(UIAction(title: lastHistoryLabel) { (action) in
                                var children = self.historyMenu.children
                                if let index = children.firstIndex(of: action) {
                                    children.removeLast(children.count - index)
                                    self.historyMenu = self.historyMenu.replacingChildren(children)
                                    if var rightBarButtonItems = self.navigationItem.rightBarButtonItems {
                                        rightBarButtonItems[0] = UIBarButtonItem(image: UIImage(systemName: "clock"), menu: self.historyMenu)
                                        self.navigationItem.setRightBarButtonItems(rightBarButtonItems, animated: true)
                                    }
                                    self.pdfView!.go(to: curPage)
                                }
                            })
                            self.historyMenu = self.historyMenu.replacingChildren(historyItems)
                            if let rightBarButtonItems = self.navigationItem.rightBarButtonItems {
                                rightBarButtonItems[0].menu = self.historyMenu
                                    //= UIBarButtonItem(image: UIImage(systemName: "clock"), menu: self.historyMenu)
                                //self.navigationItem.setRightBarButtonItems(rightBarButtonItems, animated: true)
                            }
                            //self.navigationItem.setRightBarButtonItems([UIBarButtonItem(image: UIImage(systemName: "clock"), menu: self.historyMenu)], animated: true)
                        }
                        self.pdfView!.go(to: dest)
                    }
                })
                
            }
        }
        
        navigationItem.setRightBarButtonItems(
            [
                UIBarButtonItem(image: UIImage(systemName: "clock"), menu: historyMenu),
                UIBarButtonItem(title: "Zoom In", image: UIImage(systemName: "plus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
                    self.pdfView?.scaleFactor = (self.pdfView?.scaleFactor ?? 1.0) * 1.1
                })),
                UIBarButtonItem(title: "Zoom Out", image: UIImage(systemName: "minus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
                    self.pdfView?.scaleFactor = (self.pdfView?.scaleFactor ?? 1.0) / 1.1
                }))
        ], animated: true)
        
        let navContentsMenu = UIMenu(title: "Contents", children: contents)
        
        //navigationItem.setRightBarButton(UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        //navigationItem.setRightBarButtonItems([UIBarButtonItem(image: UIImage(systemName: "list.bullet"), menu: navContentsMenu)], animated: true)
        
        
        thumbController.view = thumbImageView
        
        titleInfoButton.setTitle("Title", for: .normal)
        titleInfoButton.setTitleColor(.label, for: .normal)
        titleInfoButton.showsMenuAsPrimaryAction = true
        titleInfoButton.menu = navContentsMenu
        titleInfoButton.frame = CGRect(x:0, y:0, width: 200, height: 40);
        
        navigationItem.titleView = titleInfoButton
        
        self.view = pdfView
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.viewSafeAreaInsetsDidChange()
        self.viewLayoutMarginsDidChange()
        //self.additionalSafeAreaInsets = .init(top: <#T##CGFloat#>, left: <#T##CGFloat#>, bottom: <#T##CGFloat#>, right: <#T##CGFloat#>)
        
        let bookReadingPosition = bookDetailView?.book.readPos.getPosition(UIDevice().name)
        if( bookReadingPosition != nil ) {
            let destPageNum = (bookReadingPosition?.lastPosition[0] ?? 1) - 1
            if ( destPageNum >= 0 ) {
                if let page = pdfView?.document?.page(at: destPageNum) {
                    pdfView?.go(to: page)
                }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        var position = [String : Any]()
        position["pageNumber"] = pdfView?.currentPage?.pageRef?.pageNumber ?? 1
        position["pageOffsetX"] = CGFloat(0)
        position["pageOffsetY"] = CGFloat(0)
        bookDetailView?.updateCurrentPosition(position)
    }
    
    class PDFPageWithBackground : PDFPage {
        override func draw(with box: PDFDisplayBox, to context: CGContext) {
            // Draw rotated overlay string
            UIGraphicsPushContext(context)
            context.saveGState()

            context.setFillColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
            
            let rect = self.bounds(for: box)
            
            context.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))

            context.restoreGState()
            UIGraphicsPopContext()
            
            // Draw original content
            super.draw(with: box, to: context)
            
            print("context \(box.rawValue) \(context.height) \(context.width)")
            
            return
            
            
        }
    }
    
    func classForPage() -> AnyClass {
        return PDFPageWithBackground.self
    }
    
    @objc private func handlePageChange(notification: Notification)
    {
        var titleLabel = self.bookTitle
        if var outlineRoot = pdfView?.document?.outlineRoot {
            while outlineRoot.numberOfChildren == 1 {
                outlineRoot = outlineRoot.child(at: 0)!
            }
            if let curPage = self.pdfView?.currentPage {
                if let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)) {
                    if !curPageSelection.selectionsByLine().isEmpty, var curPageOutlineItem = pdfView?.document?.outlineItem(for: curPageSelection) {
                        while( curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot) {
                            curPageOutlineItem = curPageOutlineItem.parent!
                        }
                        if curPageOutlineItem.label != nil && !curPageOutlineItem.label!.isEmpty {
                            titleLabel = curPageOutlineItem.label
                        }
                    }
                }
            }
        }
        self.titleInfoButton.setTitle(titleLabel, for: .normal)
        

//        setToolbarItems(
//            [   UIBarButtonItem(customView: self.pageSlider),
//                UIBarButtonItem(title: "\(pdfView?.currentPage?.pageRef?.pageNumber ?? 1) / \(pdfView?.document?.pageCount ?? 1)"),
//                UIBarButtonItem.flexibleSpace()
//            ], animated: false)
        let curPageNum = pdfView?.currentPage?.pageRef?.pageNumber ?? 1
        pageIndicator.setTitle("\(curPageNum) / \(pdfView?.document?.pageCount ?? 1)", for: .normal)
        pageSlider.setValue(Float(curPageNum), animated: true)
        
        print("handlePageChange \(notification)")
        
        
        if let page = pdfView?.currentPage {
            print("pageNumber \(page.pageRef?.pageNumber)")
            
            let bound = page.bounds(for: .cropBox)
            let image = page.thumbnail(of: CGSize(width: bound.width / 4, height: bound.height / 4), for: .cropBox)
            
            let cgimage = image.cgImage
            let provider = cgimage!.dataProvider
            let providerData = provider!.data
            let data = CFDataGetBytePtr(providerData)
            
            let numberOfComponents = 4
            
            var top = 0
            var bottom = 0
            var leading = 0
            var trailing = 0
            
            print("width=\(cgimage!.width) height=\(cgimage!.height)")
            
            let align = 8
            let padding = align - cgimage!.width % align
            print("CGIMAGE PADDING \(padding)")
            
            //TOP
            for h in (0..<(cgimage!.height/4)) {
                var isWhite = true
                for w in (0..<cgimage!.width) {
                    
                    let pixelData = ((Int(cgimage!.width + padding) * h) + w) * numberOfComponents
                    
                    let r = data![pixelData]
                    let g = data![pixelData + 1]
                    let b = data![pixelData + 2]
                    let a = data![pixelData + 3]
                    // print("\(h) \(w) \(r) \(g) \(b) \(a)")
                    
                    if r < 250 && g < 250 && b < 250 {
                        isWhite = false
                        print("top \(h) \(w) \(r) \(g) \(b) \(a)")
                        break
                    }
//
                }
                //print("isWhite h=\(h) \(isWhite)")
                if !isWhite {
                    top = h
                    break
                }
            }
            
            //BOTTOM
            for h in (0..<(cgimage!.height/4)) {
                var isWhite = true
                for w in (0..<cgimage!.width) {
                    
                    let pixelData = ((Int(cgimage!.width + padding) * (cgimage!.height - h - 1)) + w) * numberOfComponents
                    
                    let r = data![pixelData]
                    let g = data![pixelData + 1]
                    let b = data![pixelData + 2]
                    let a = data![pixelData + 3]
                    //print("\(h) \(w) \(r) \(g) \(b) \(a)")
                    
                    if r < 250 && g < 250 && b < 250 {
                        isWhite = false
                        print("bottom \(cgimage!.height - h - 1) \(w) \(r) \(g) \(b) \(a)")
                        break
                    }
                }
                //print("isWhite h=\(h) \(isWhite)")
                if !isWhite {
                    bottom = cgimage!.height - h - 1
                    break
                }
            }
            
            //LEADING
            for w in (0..<(cgimage!.width/4)) {
                var isWhite = true
                for h in (0..<(cgimage!.height)){
                    let pixelData = ((Int(cgimage!.width + padding) * (h)) + w) * numberOfComponents
                    
                    let r = data![pixelData]
                    let g = data![pixelData + 1]
                    let b = data![pixelData + 2]
                    let a = data![pixelData + 3]
                    //print("\(h) \(w) \(r) \(g) \(b) \(a)")
                    
                    if r < 250 && g < 250 && b < 250 {
                        isWhite = false
                        print("leading \(h) \(w) \(r) \(g) \(b) \(a)")
                        break
                    }
                }
                //print("isWhite w=\(w) \(isWhite)")
                if !isWhite {
                    leading = w
                    break
                }
            }
            
            //TRAILING
            for w in (0..<(cgimage!.width/4)) {
                var isWhite = true
                for h in (0..<(cgimage!.height)){
                    let pixelData = ((Int(cgimage!.width + padding) * (h)) + (cgimage!.width - w - 1)) * numberOfComponents
                    
                    let r = data![pixelData]
                    let g = data![pixelData + 1]
                    let b = data![pixelData + 2]
                    let a = data![pixelData + 3]
                    //print("\(h) \(w) \(r) \(g) \(b) \(a)")
                    
                    if r < 250 && g < 250 && b < 250 {
                        isWhite = false
                        print("trailing \(h) \(cgimage!.width - w - 1) \(r) \(g) \(b) \(a)")
                        break
                    }
                }
                //print("isWhite w=\(w) \(isWhite)")
                if !isWhite {
                    trailing = cgimage!.width - w - 1
                    break
                }
            }
            //print("pageNumber \(page.pageRef?.pageNumber)")
            
            let imageSize = image.size
            UIGraphicsBeginImageContextWithOptions(imageSize, false, CGFloat.zero)
            image.draw(at: CGPoint.zero)
            let rectangle = CGRect(x: leading, y: top, width: trailing - leading + 1, height: bottom - top)
            UIColor.black.setFill()
            //UIRectFill(rectangle)
            UIRectFrame(rectangle)
            
            UIColor.red.setFill()
            UIRectFrame(bound)
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            self.thumbImageView.image = newImage
            
            if let curScale = pdfView?.scaleFactor, curScale > 0 {
                
                let visibleWidthRatio = 1.0 * Double(trailing - leading + 1) / Double(cgimage!.width)
                let visibleHeightRatio = 1.0 * Double(bottom - top + 1) / Double(cgimage!.height)
                let scale = 0.93 / visibleWidthRatio

                print("curScale \(curScale) \(visibleWidthRatio) \(visibleHeightRatio)")
                
                if scale > 1 {
                    pdfView?.scaleFactor = curScale * CGFloat(scale)
                    
                    var pdfDest = pdfView?.currentDestination
                    var curPoint = pdfDest!.point
                    let newDest = PDFDestination(page: page, at: CGPoint(x: curPoint.x, y: 0))
                    print("POINT \(pdfDest!.point) \(page.bounds(for: .cropBox)) \(pdfView!.documentView)")
                    
                    while curPoint.x < 0.0 {
                        self.pdfView!.scaleFactor = self.pdfView!.scaleFactor * 1.1
                        pdfDest = pdfView!.currentDestination
                        curPoint = pdfDest!.point
                        print("CURPOINT \(curPoint) \(self.pdfView!.scaleFactor)")
                    }
                    while curPoint.x > 20.0 {
                        self.pdfView!.scaleFactor = self.pdfView!.scaleFactor / 1.1
                        pdfDest = pdfView!.currentDestination
                        curPoint = pdfDest!.point
                        print("CURPOINT \(curPoint) \(self.pdfView!.scaleFactor)")
                    }
                    
                    
                    
                    //pdfView?.go(to: newDest)
                    // pdfView?.go(to: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), on: page)
                    
                    
                }
            }
        }
        
        
    }
    
    @objc func handleScaleChange(_ sender: Any?)
    {
        self.lastScale = pdfView!.scaleFactor
    }
}
