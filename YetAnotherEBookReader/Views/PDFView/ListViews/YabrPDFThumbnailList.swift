//
//  FolioReaderBookList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import PDFKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFThumbnailList: UICollectionViewController {
    var yabrPDFView: YabrPDFView? {
        (self.parent as? YabrPDFNavigationPageVC)?.yabrPDFView
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        (self.parent as? YabrPDFNavigationPageVC)?.yabrPDFMetaSource
    }
    var palette: PDFThemePalette {
        (parent as? YabrPDFNavigationPageVC)?.pdfViewController?.pdfOptions.themePalette ?? PDFThemePalette(themeMode: .none)
    }
    var listStyle: PDFThemePalette.ListStyle { palette.listStyle }

    fileprivate let layout = UICollectionViewFlowLayout()

    fileprivate var topLevelOutlines = [PDFOutline]()

    /// Thumbnails render off the main thread, one at a time, newest request
    /// first served; a cell scrolled away cancels its render.
    private let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var renders: [Int: Operation] = [:]
    /// Keyed by page index; cleared when the item size changes.
    private let thumbnails = NSCache<NSNumber, UIImage>()
    private var thumbnailSize: CGSize = .zero
    
    init() {
        layout.itemSize = .init(width: 300, height: 400)
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16
        layout.headerReferenceSize = .init(width: 100, height: 40)
        layout.sectionHeadersPinToVisibleBounds = true
        
        super.init(collectionViewLayout: layout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.collectionView.register(YabrPDFThumbnailListCell.self, forCellWithReuseIdentifier: kReuseCellIdentifier)
        self.collectionView.register(YabrPDFThumbnailSectionCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: kReuseHeaderFooterIdentifier)
        
        self.collectionView.backgroundColor = listStyle.background
        
        if var outlineRoot = yabrPDFView?.document?.outlineRoot {
            while outlineRoot.numberOfChildren == 1, let child = outlineRoot.child(at: 0) {
                outlineRoot = child
            }
            
            for i in 0..<outlineRoot.numberOfChildren {
                if let child = outlineRoot.child(at: i) {
                    topLevelOutlines.append(child)
                }
            }
        }
        
        if topLevelOutlines.first?.destination?.page?.pageRef?.pageNumber != 1 {
            if let firstPage = yabrPDFView?.document?.page(at: 0) {
                let firstPageOutline = PDFOutline()
                firstPageOutline.destination = PDFDestination(page: firstPage, at: .zero)
                topLevelOutlines.insert(firstPageOutline, at: 0)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard let currentPageNumber = yabrPDFView?.currentPage?.pageRef?.pageNumber,
              let sectionIndex = YabrPDFChapterList.currentIndex(
                startPages: topLevelOutlines.map { $0.destination?.page?.pageRef?.pageNumber },
                currentPage: currentPageNumber
              ),
              let start = topLevelOutlines[sectionIndex].destination?.page?.pageRef?.pageNumber
        else { return }
        let row = currentPageNumber - start
        guard row >= 0, row < collectionView(collectionView, numberOfItemsInSection: sectionIndex) else { return }
        self.collectionView.scrollToItem(at: IndexPath(row: row, section: sectionIndex), at: .centeredVertically, animated: true)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let minWidth = 185.0
        
        let itemCount = floor(self.collectionView.frame.size.width / minWidth)
        let itemWidth = floor((self.collectionView.frame.size.width - layout.minimumInteritemSpacing*(itemCount-1)) / itemCount)
        let itemHeight = itemWidth * 1.333 + 80
        layout.itemSize = .init(width: itemWidth, height: itemHeight)
        let size = CGSize(width: itemWidth - 32, height: itemWidth * 1.333)
        if size != thumbnailSize {
            thumbnailSize = size
            thumbnails.removeAllObjects()
        }
    }

    // MARK: - collection view data source
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return topLevelOutlines.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let outline = topLevelOutlines[section]
        if section < topLevelOutlines.count - 1 {
            let nextOutline = topLevelOutlines[section + 1]
            return max(0, (nextOutline.destination?.page?.pageRef?.pageNumber ?? 0) - (outline.destination?.page?.pageRef?.pageNumber ?? 0))
        } else {
            //last one
            return max(0, (yabrPDFView?.document?.pageCount ?? 0) + 1 - (outline.destination?.page?.pageRef?.pageNumber ?? 0))
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kReuseHeaderFooterIdentifier, for: indexPath) as! YabrPDFThumbnailSectionCell
        
        let style = listStyle
        headerView.titleLabel.text = topLevelOutlines[indexPath.section].label
        headerView.titleLabel.font = style.titleFont()
        headerView.titleLabel.textColor = style.text
        headerView.contentView.backgroundColor = style.background
        
        return headerView
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFThumbnailListCell
        
        let outline = topLevelOutlines[indexPath.section]
        guard let outlinePageNumber = outline.destination?.page?.pageRef?.pageNumber,
              let page = yabrPDFView?.document?.page(at: outlinePageNumber - 1 + indexPath.row)
        else { return cell }

        let pageNumber = outlinePageNumber + indexPath.row
        let pageIndex = pageNumber - 1
        let style = listStyle
        cell.configure(title: "Page \(pageNumber)", isCurrent: pageNumber == yabrPDFView?.currentPage?.pageRef?.pageNumber, style: style)
        cell.representedPage = pageIndex

        let bounds = page.bounds(for: .cropBox)
        let quarterTurns = abs(page.rotation / 90) % 2
        let aspect = bounds.height > 0 && bounds.width > 0
            ? (quarterTurns == 1 ? bounds.height / bounds.width : bounds.width / bounds.height)
            : 3.0 / 4.0
        if let image = thumbnails.object(forKey: pageIndex as NSNumber) {
            cell.setThumbnail(image, pageAspect: aspect)
        } else {
            cell.setThumbnail(nil, pageAspect: aspect)
            requestThumbnail(of: page, at: pageIndex, palette: palette, aspect: aspect, for: cell)
        }
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let pageIndex = (cell as? YabrPDFThumbnailListCell)?.representedPage else { return }
        renders.removeValue(forKey: pageIndex)?.cancel()
    }

    /// Renders like the page: inverted under dark, under the surface's alpha
    /// overlay for the light tints (it turns the white page into the theme colour).
    nonisolated static func renderThumbnail(of page: PDFPage, size: CGSize, palette: PDFThemePalette) -> UIImage {
        let image = page.thumbnail(of: size, for: .cropBox)
        if palette.drawsInverted {
            guard let cgImage = image.cgImage, let invertedImage = YabrPDFView.invertedImage(cgImage) else { return image }
            return UIImage(cgImage: invertedImage, scale: image.scale, orientation: .up)
        }
        guard let overlay = palette.overlay else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: image.size)
            UIColor.white.setFill()
            context.fill(rect)
            image.draw(in: rect)
            // As `PDFReaderSurface.themeOverlayView` composites over the page.
            UIColor(red: overlay.red, green: overlay.green, blue: overlay.blue, alpha: overlay.alpha).setFill()
            context.fill(rect, blendMode: .normal)
        }
    }

    private func requestThumbnail(of page: PDFPage, at pageIndex: Int, palette: PDFThemePalette, aspect: CGFloat, for cell: YabrPDFThumbnailListCell) {
        guard renders[pageIndex] == nil else { return }
        let size = thumbnailSize == .zero ? layout.itemSize : thumbnailSize
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation, weak cell] in
            guard operation?.isCancelled == false else { return }
            let image = Self.renderThumbnail(of: page, size: size, palette: palette)
            DispatchQueue.main.async {
                guard let self else { return }
                self.renders.removeValue(forKey: pageIndex)
                self.thumbnails.setObject(image, forKey: pageIndex as NSNumber)
                if let cell, cell.representedPage == pageIndex {
                    cell.setThumbnail(image, pageAspect: aspect)
                }
            }
        }
        renders[pageIndex] = operation
        renderQueue.addOperation(operation)
    }

    deinit {
        renderQueue.cancelAllOperations()
    }

    // MARK: - Table view delegate

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let outline = topLevelOutlines[indexPath.section]
        if let outlinePageNumber = outline.destination?.page?.pageRef?.pageNumber,
           let page = yabrPDFView?.document?.page(at: outlinePageNumber - 1 + indexPath.row) {
//            let destination = PDFDestination(page: page, at: .zero)
//            yabrPDFMetaSource?.yabrPDFNavigate(yabrPDFView, destination: destination)
            if let curPage = yabrPDFView?.currentPage {
                yabrPDFView?.yabrPDFViewController?.updateHistoryMenu(curPage: curPage)
            }
            yabrPDFView?.go(to: page)
        }
        
        self.dismiss(animated: true)
    }
}
