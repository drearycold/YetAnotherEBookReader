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
import SwiftUI

@available(macCatalyst 14.0, *)
class YabrPDFViewController: UIViewController, UIGestureRecognizerDelegate, ObservableObject {
    let pdfView = YabrPDFView()
    let pdfViewAux = YabrPDFView()
    
    let thumbController = UIViewController()

    let blankView = UIImageView()
    let blankActivityView = UIActivityIndicatorView()
    
    let logger = Logger()
    
    var historyMenu = UIMenu(title: "History", children: [])
    var pdfViewBottomConstraint: NSLayoutConstraint?
    var chromeContainerWidthConstraint: NSLayoutConstraint?
    var chromeContainerHeightConstraint: NSLayoutConstraint?
    
    let chromeContainerView = UIView()
    let stackView = UIStackView()
    
    let pageSlider = UISlider()
    let pageIndicator = UIButton()
    let pageNextButton = UIButton()
    let pagePrevButton = UIButton()
    let pageBackButton = UIButton()
    let pageAuxButton = UIButton()
    
    let annotationView = YabrPDFAnnotationView()
    
    let shareBarButtonItem = UIBarButtonItem()
    
    let titleInfoButton = UIButton()
    var tocList = [(String, Int)]()
    
    let thumbImageView = UIImageView()
    
    var yabrPDFMetaSource: YabrPDFMetaSource?
    weak var readerEngineDelegate: ReaderEngineDelegate?
    var initialPosition: ReaderEnginePosition?
    
    lazy var annotationManager: PDFAnnotationManager = {
        let bookId = yabrPDFMetaSource?.yabrPDFBook(pdfView, info: "Key") ?? ""
        return PDFAnnotationManager(pdfView: pdfView, delegate: readerEngineDelegate, bookId: bookId)
    }()
    lazy var bookmarkManager = PDFBookmarkManager(pdfView: pdfView, metaSource: yabrPDFMetaSource)
    lazy var searchController = PDFSearchController(pdfView: pdfView, metaSource: yabrPDFMetaSource)
    lazy var marginCropController = PDFMarginCropController(
        pdfView: pdfView,
        blankView: blankView,
        blankActivityView: blankActivityView
    )
    
    @Published var pdfOptions = PDFPreferenceValue() {
        didSet {
            PDFPageWithBackground.fillColor = pdfOptions.fillColor
            
            let backgroundColor = UIColor(cgColor: pdfOptions.fillColor)
            self.navigationController?.navigationBar.barTintColor = backgroundColor
            self.navigationController?.navigationBar.backgroundColor = backgroundColor
            self.navigationController?.toolbar.barTintColor = backgroundColor
            self.navigationController?.toolbar.backgroundColor = backgroundColor
            self.tabBarController?.tabBar.barTintColor = backgroundColor
            self.tabBarController?.tabBar.backgroundColor = backgroundColor
            applyChromeTheme()
            
            self.pdfView.backgroundColor = backgroundColor
            
            guard let curPage = self.pdfView.currentPage,
                  let curPageNum = curPage.pageRef?.pageNumber else { return }
            
            if oldValue.pageMode != pdfOptions.pageMode || oldValue.scrollDirection != pdfOptions.scrollDirection {
                updatePageViewPositionHistory()
            }
            
            switch pdfOptions.pageMode {
            case .Page:
                self.pdfView.displayMode = .singlePage
                switch pdfOptions.readingDirection {
                case .LtR_TtB:
                    pageSlider.semanticContentAttribute = .forceLeftToRight
                    pdfView.displaysRTL = false
                    pdfView.displayDirection = .vertical
                case .TtB_RtL:
                    pageSlider.semanticContentAttribute = .forceRightToLeft
                    pdfView.displaysRTL = true
                    pdfView.displayDirection = .horizontal
                }
            case .Scroll:
                self.pdfView.displayMode = .singlePageContinuous
                pageSlider.semanticContentAttribute = .forceLeftToRight
                pdfView.displaysRTL = false
                switch pdfOptions.scrollDirection {
                case .Vertical:
                    pdfView.displayDirection = .vertical
                case .Horizontal:
                    pdfView.displayDirection = .horizontal
                }
            }
            
            if oldValue.pageMode != pdfOptions.pageMode || oldValue.scrollDirection != pdfOptions.scrollDirection {
                if let firstPage = pdfView.document?.page(at: 1) {
                    pdfView.go(to: PDFDestination(page: firstPage, at: .zero))
                }
                
                let viewPosition = getPageViewPositionHistory(curPageNum)?.point
                if viewPosition != nil {
                    pdfView.go(to: PDFDestination(page: curPage, at: viewPosition!))
                } else {
                    pdfView.go(to: curPage)
                }
                
                if pdfOptions.pageMode == .Page {
                    self.marginCropController.clearCache()
                }
            }
            
            if pdfOptions.pageMode == .Page {
                pdfView.pageTapResize(hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
            } else {
                pdfView.pageTapDisable()
            }
            
            yabrPDFMetaSource?.yabrPDFOptions(pdfView, update: pdfOptions)
        }
    }
        
    var pageViewPositionHistory = [Int: PageViewPosition]() //key is 1-based (pdfView.currentPage?.pageRef?.pageNumber)
    
    func open() -> Int {
        guard let pdfURL = yabrPDFMetaSource?.yabrPDFURL(pdfView) else { return -1 }
        
        logger.info("pdfURL: \(pdfURL.absoluteString)")
        logger.info("Exist: \(FileManager.default.fileExists(atPath: pdfURL.path))")
        
        guard let pdfDoc = PDFDocument(url: pdfURL) else { return -1 }
        
        pdfDoc.delegate = self
        logger.info("pdfDoc: \(pdfDoc.majorVersion) \(pdfDoc.minorVersion)")
        pdfView.document = pdfDoc
        
        pdfView.displayMode = PDFDisplayMode.singlePage
        pdfView.displayDirection = PDFDisplayDirection.horizontal
        pdfView.interpolationQuality = PDFInterpolationQuality.high
        
        if let preferences = yabrPDFMetaSource?.yabrPDFOptions(pdfView) {
            self.pdfOptions = preferences
        }
        
        if let position = initialPosition {
            let intialPageNum = position.pageNumber > 0 ? position.pageNumber : 1
        
            pageViewPositionHistory.removeAll()
            
            pageViewPositionHistory[intialPageNum] = PageViewPosition(
                scaler: pdfOptions.lastScale,
                point: CGPoint(x: position.pageOffsetX, y: position.pageOffsetY)
            )
        }
        
        return 0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // pdfView.usePageViewController(true, withViewOptions: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageChange(notification:)), name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScaleChange(_:)), name: .PDFViewScaleChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDisplayBoxChange(_:)), name: .PDFViewDisplayBoxChanged, object: pdfView)
        
        pdfView.autoScales = false

        configureReaderChrome()
        configureSelectionOverlay()
        
        self.annotationManager.injectAllHighlights()
        
        
        marginCropController.configureBlankOverlay()
        
        pdfView.prepareActions(pageNextButton: pageNextButton, pagePrevButton: pagePrevButton)
        
        configureThumbnailPreview()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
//        self.viewSafeAreaInsetsDidChange()
//        self.viewLayoutMarginsDidChange()
        
//        UIMenuController.shared.menuItems = [UIMenuItem(title: "StarDict", action: #selector(lookupStarDict))]
//        starDictView.loadViewIfNeeded()
        if pdfOptions.pageMode == .Page {
            pdfView.pageTapPreview(hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
        }
        let destPageIndex = (pageViewPositionHistory.first?.key ?? 1) - 1 //convert from 1-based to 0-based
        
        if let page = pdfView.document?.page(at: destPageIndex) {
            if page.pageRef?.pageNumber != self.pdfView.currentPage?.pageRef?.pageNumber {
                self.addBlankSubView(page: page)
            }
            self.pdfView.goToFirstPage(self)
            self.pdfView.go(to: page)
            
//                if self.pdfView.currentPage?.pageRef?.pageNumber != destPageIndex {
//                    delay(0.2) {
//                        self.pdfView.go(to: page)
//                    }
//                }
        }
        
        if destPageIndex == 0 {
            self.handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        updatePageViewPositionHistory()
        
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            
        } completion: { [self] _ in
            handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
            if pdfOptions.pageMode == .Page {
                pdfView.pageTapPreview(hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
            } else {
                pdfView.pageTapDisable()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateChromeContainerLayout()
    }
    
    func addBlankSubView(page: PDFPage?) {
        marginCropController.showBlankOverlay(page: page, options: pdfOptions)
    }
    
    func clearBlankSubView() {
        marginCropController.hideBlankOverlay()
    }
    
}

extension YabrPDFViewController: PDFDocumentDelegate {
    func classForPage() -> AnyClass {
        return PDFPageWithBackground.self
    }
}

extension YabrPDFViewController: PDFViewDelegate {
    func pdfViewParentViewController() -> UIViewController {
        return self
    }
}

protocol YabrPDFMetaSource {
    func yabrPDFBook(_ view: YabrPDFView?, info: String) -> String?
    
    func yabrPDFURL(_ view: YabrPDFView?) -> URL?
    
    func yabrPDFDocument(_ view: YabrPDFView?) -> PDFDocument?
    
    func yabrPDFNavigate(_ view: YabrPDFView?, pageNumber: Int, offset: CGPoint)
    
    func yabrPDFNavigate(_ view: YabrPDFView?, destination: PDFDestination)

    func yabrPDFOutline(_ view: YabrPDFView?, for page: Int) -> PDFOutline?
    

    
    func yabrPDFOptions(_ view: YabrPDFView?) -> PDFPreferenceValue?
    
    func yabrPDFOptions(_ view: YabrPDFView?, update options: PDFPreferenceValue)
    
    func yabrPDFDictViewer(_ view: YabrPDFView?) -> (String, UINavigationController)?
    
    func yabrPDFBookmarks(_ view: YabrPDFView?) -> [PDFBookmark]
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, update bookmark: PDFBookmark)
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, remove bookmark: PDFBookmark)
    
    func yabrPDFHighlights(_ view: YabrPDFView?) -> [PDFHighlight]
    
    func yabrPDFHighlights(_ view: YabrPDFView?, getById highlightId: UUID) -> PDFHighlight?
    
    func yabrPDFHighlights(_ view: YabrPDFView?, update highlight: PDFHighlight)
    
    func yabrPDFHighlights(_ view: YabrPDFView?, remove highlight: PDFHighlight)
    
    func yabrPDFReferenceText(_ view: YabrPDFView?) -> String?

    func yabrPDFReferenceText(_ view: YabrPDFView?, set refText: String?)
    
    func yabrPDFOptionsIsNight<T>(_ view: YabrPDFView?, _ f: T, _ l: T) -> T
}
