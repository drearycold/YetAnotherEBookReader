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

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFViewController: UIViewController, UIGestureRecognizerDelegate, ObservableObject {
    /// Hosts the page views; see `PDFReaderSurface`.
    let surface = PDFReaderSurface()
    /// The page view on screen. Read it at the point of use; never store it.
    var pdfView: YabrPDFView { surface.activeView }
    /// The floating reference view (the chrome's aux button).
    let auxSurface = PDFReaderSurface()
    var pdfViewAux: YabrPDFView { auxSurface.activeView }
    
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
    
    let shareBarButtonItem = UIBarButtonItem()
    
    let titleInfoButton = UIButton()
    var tocList = [(String, Int)]()
    
    var yabrPDFMetaSource: YabrPDFMetaSource?
    weak var readerEngineDelegate: ReaderEngineDelegate?
    var initialPosition: ReaderEnginePosition?
    
    lazy var annotationManager: PDFAnnotationManager = {
        // The id the highlights are read back with, not the shelf identity.
        let bookId = yabrPDFMetaSource?.yabrPDFBook(pdfView, info: "PrefId") ?? ""
        return PDFAnnotationManager(surface: surface, delegate: readerEngineDelegate, bookId: bookId)
    }()
    lazy var bookmarkManager = PDFBookmarkManager(surface: surface, metaSource: yabrPDFMetaSource)
    lazy var searchController = PDFSearchController(surface: surface, metaSource: yabrPDFMetaSource)
    lazy var menuManager = PDFMenuManager(controller: self)
    /// The search sheet's list, kept while the reader is open so reopening
    /// shows the last query and its results, as FolioReader's search does.
    lazy var searchList: YabrPDFSearchList = {
        let list = YabrPDFSearchList()
        list.hostController = self
        list.title = "Search"
        return list
    }()
    let marginCropController = PDFMarginCropController()

    /// Read by `PDFPageWithBackground.draw` on PDFKit's render threads.
    nonisolated let pageRenderTheme = PDFPageRenderTheme()

    /// Page number (1-based) of a pending jump; `handlePageChange` shows the jump
    /// mask once that page's viewport is applied.
    var pendingJumpMaskPage: Int?
    /// Where a page read in steps (#97) lands when the page change under way is
    /// handled.
    let readingFlow = PDFReadingFlowController()
    /// Set while `invalidateRenderedPages` re-attaches the document; PDFKit's page
    /// changes meanwhile are not the reader's.
    var isReattachingDocument = false
    /// Set while `handleScaleChange` stores the page view's scale.
    var isRecordingScale = false
    /// A tap's pending reveal of the hidden bars; see `requestBarToggle`.
    var pendingBarReveal: DispatchWorkItem?
    static let barRevealDelay: TimeInterval = 0.3
    /// PDF Options is open; the bars stay hidden until it closes.
    var isPresentingOptions = false
    
    @Published var pdfOptions = PDFPreferenceValue() {
        didSet {
            if isRecordingScale {
                // PDFKit rescaled (every fitted page turn): only remember the scale.
                yabrPDFMetaSource?.yabrPDFOptions(pdfView, update: pdfOptions)
                return
            }

            applyThemePalette()

            let backgroundColor = UIColor(cgColor: pdfOptions.fillColor)
            self.navigationController?.toolbar.barTintColor = backgroundColor
            self.navigationController?.toolbar.backgroundColor = backgroundColor
            self.tabBarController?.tabBar.barTintColor = backgroundColor
            self.tabBarController?.tabBar.backgroundColor = backgroundColor
            applyChromeTheme()

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
                self.pdfView.restoreDefaultPageBreakMargins()
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
                markJumpTarget(curPage)
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
                surface.pageTapResize(hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
            } else {
                surface.pageTapDisable()
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageChange(notification:)), name: .readerSurfacePageChanged, object: surface)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScaleChange(_:)), name: .readerSurfaceScaleChanged, object: surface)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDisplayBoxChange(_:)), name: .readerSurfaceDisplayBoxChanged, object: surface)
        
        pdfView.autoScales = false
        surface.drawLog = pageRenderTheme
        surface.onCoverEnded = { [weak self] in
            DispatchQueue.main.async { self?.refreshPageBuffers() }
        }
        // The bars float over the page (see `pageLayoutInsets`); keep the view
        // under them whatever their appearance.
        extendedLayoutIncludesOpaqueBars = true
        surface.onUserScroll = { [weak self] in
            self?.setReaderBarsHidden(true, animated: true)
        }
        // Turning with the toolbar's arrows keeps the toolbar, and the bars, up.
        surface.onTapZonePageTurn = { [weak self] in
            self?.setReaderBarsHidden(true, animated: true)
        }
        surface.onPageTap = { [weak self] in
            self?.requestBarToggle()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleSelectionChangeForBars(_:)), name: .PDFViewSelectionChanged, object: nil)

        configureReaderChrome()
        configureSelectionMenus()
        
        self.annotationManager.injectAllHighlights()
        
        
        surface.prepareActions(pageNextButton: pageNextButton, pagePrevButton: pagePrevButton)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let navigationBar = navigationController?.navigationBar {
            pdfOptions.themePalette.apply(to: navigationBar)
        }
        // Hide PDFKit's placeholder and the unfitted first layout until the first
        // page is positioned.
        surface.showLoadingCover()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
//        self.viewSafeAreaInsetsDidChange()
//        self.viewLayoutMarginsDidChange()
        
//        starDictView.loadViewIfNeeded()
        if pdfOptions.pageMode == .Page {
            surface.pageTapPreview(hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
        }
        let destPageIndex = (pageViewPositionHistory.first?.key ?? 1) - 1 //convert from 1-based to 0-based
        
        if let page = pdfView.document?.page(at: destPageIndex) {
            self.pdfView.goToFirstPage(self)
            markJumpTarget(page)
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
        surface.finishLoadingCover()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        updatePageViewPositionHistory()
        let region = readingRegionOnScreen()
        
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            
        } completion: { [self] _ in
            if let region {
                readingFlow.setPendingTarget(.region(region.region), pageNumber: region.pageNumber)
            }
            handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
            if pdfOptions.pageMode == .Page {
                surface.pageTapPreview(hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
            } else {
                surface.pageTapDisable()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateChromeContainerLayout()
    }
    
    /// The page after (`forward`) or before the current one in document order.
    func adjacentPage(forward: Bool) -> PDFPage? {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        let index = document.index(for: page) + (forward ? 1 : -1)
        guard index >= 0, index < document.pageCount else { return nil }
        return document.page(at: index)
    }

    /// Turns to the next (`forward`) or previous page in document order. A rendered
    /// buffer of that page becomes the page view; otherwise PDFKit turns, covered
    /// by a buffer or, under dark, a snapshot.
    func turnPage(forward: Bool) {
        updatePageViewPositionHistory()
        // A page read in steps (#97) is read through them first.
        if stepWithinPage(forward: forward) {
            return
        }
        // Arriving forward reads a page in steps from its start; back, from its end.
        let arrival: PDFReadingTarget = forward ? .first : .last
        let target = adjacentPage(forward: forward)
        if let pageNumber = target?.pageRef?.pageNumber {
            readingFlow.setPendingTarget(arrival, pageNumber: pageNumber)
        }
        if pdfView.displayMode == .singlePage,
           let target,
           surface.takeOver(showing: target, viewport: { [unowned self] page, view in
               singlePageViewport(for: page, in: view, target: arrival).fit
           }) {
            return
        }

        coverPageTurnIfNeeded(forward: forward)
        if forward {
            pdfView.goToNextPage(nil)
        } else {
            pdfView.goToPreviousPage(nil)
        }
    }

    /// Dark page turns: PDFKit's page transition starts before `handlePageChange`
    /// can cover it, so freeze the current page first; `handlePageChange` then
    /// swaps in the new page. Not needed when the target page's buffer has
    /// rendered: it covers the page change exactly, and a snapshot's glyphs render
    /// a little heavier than PDFKit's tiles, which shows as the mask fades. An
    /// unrendered buffer would show PDFKit's white placeholder.
    func coverPageTurnIfNeeded(forward: Bool) {
        guard pdfOptions.themePalette.drawsInverted,
              pdfView.displayMode == .singlePage,
              let page = pdfView.currentPage
        else { return }
        if let target = adjacentPage(forward: forward), surface.hasRenderedBuffer(showing: target) {
            return
        }
        surface.freezeWithJumpMask(showing: page)
    }

    /// Call before navigating to a different page by a jump (TOC, history, slider,
    /// lists, restore). Ordinary next/prev turns do not show the mask.
    func markJumpTarget(_ page: PDFPage?) {
        guard let pageNumber = page?.pageRef?.pageNumber,
              pageNumber != pdfView.currentPage?.pageRef?.pageNumber
        else { return }
        pendingJumpMaskPage = pageNumber
    }

    func applyThemePalette() {
        let palette = pdfOptions.themePalette
        // navigationItem exists before the reader is pushed, so this also holds
        // when `open()` sets the options ahead of presentation.
        palette.apply(to: navigationItem)
        if let navigationBar = navigationController?.navigationBar {
            palette.apply(to: navigationBar)
        }
        pageRenderTheme.drawsInverted = palette.drawsInverted
        surface.applyTheme(palette)
        auxSurface.applyTheme(palette)
        pdfViewAux.invertsPagePlaceholders = palette.drawsInverted
        // The aux view shows the same pages, whose annotations `surface` owns.
        surface.highlightAppearance = palette.drawsInverted ? .dark : .standard
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController: PDFDocumentDelegate, PDFPageRenderThemeProviding {
    func classForPage() -> AnyClass {
        return PDFPageWithBackground.self
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController: PDFViewDelegate {
    func pdfViewParentViewController() -> UIViewController {
        return self
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
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
