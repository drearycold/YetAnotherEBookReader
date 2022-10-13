//
//  FolioReaderBookList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import PDFKit

class YabrPDFThumbnailList: UICollectionViewController {
    var yabrPDFView: YabrPDFView? {
        (self.parent as? YabrPDFNavigationPageVC)?.yabrPDFView
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        (self.parent as? YabrPDFNavigationPageVC)?.yabrPDFMetaSource
    }
    var backgroundColor: UIColor? {
        guard let fillColor = yabrPDFMetaSource?.yabrPDFOptions(yabrPDFView)?.fillColor
        else { return nil }
        return UIColor(cgColor: fillColor)
    }
    var textColor: UIColor? {
        yabrPDFMetaSource?.yabrPDFOptions(yabrPDFView)?.isDark(.lightText, .darkText)
    }
    
    fileprivate let layout = UICollectionViewFlowLayout()

    fileprivate var topLevelOutlines = [PDFOutline]()
    
    init() {
        layout.itemSize = .init(width: 300, height: 400)
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .vertical
        
        super.init(collectionViewLayout: layout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.collectionView.register(YabrPDFThumbnailListCell.self, forCellWithReuseIdentifier: kReuseCellIdentifier)
        self.collectionView.register(YabrPDFThumbnailSectionCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: kReuseHeaderFooterIdentifier)
        
        self.collectionView.backgroundColor = backgroundColor
        self.navigationController?.navigationBar.backgroundColor = backgroundColor
        
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
        
        // Jump to the current book
        
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let minWidth = 185.0
        
        let itemCount = floor(self.collectionView.frame.size.width / minWidth)
        let itemWidth = floor((self.collectionView.frame.size.width - layout.minimumInteritemSpacing*(itemCount-1)) / itemCount)
        let itemHeight = itemWidth * 1.333 + 80
        layout.itemSize = .init(width: itemWidth, height: itemHeight)
        layout.minimumLineSpacing = 16
        layout.headerReferenceSize = .init(width: 100, height: 40)
    }

    // MARK: - collection view data source
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return topLevelOutlines.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let outline = topLevelOutlines[section]
        if section < topLevelOutlines.count - 1 {
            let nextOutline = topLevelOutlines[section + 1]
            return (nextOutline.destination?.page?.pageRef?.pageNumber ?? 0) - (outline.destination?.page?.pageRef?.pageNumber ?? 0)
        } else {
            //last one
            return (yabrPDFView?.document?.pageCount ?? 0) + 1 - (outline.destination?.page?.pageRef?.pageNumber ?? 0)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kReuseHeaderFooterIdentifier, for: indexPath) as! YabrPDFThumbnailSectionCell
        
        headerView.titleLabel.text = topLevelOutlines[indexPath.section].label
        
        return headerView
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFThumbnailListCell

        
        let outline = topLevelOutlines[indexPath.section]
        if let outlinePageNumber = outline.destination?.page?.pageRef?.pageNumber {
            cell.titleLabel.text = "Page \(outlinePageNumber + indexPath.row)"
            cell.thumbImage.image = yabrPDFView?.document?.page(at: outlinePageNumber - 1 + indexPath.row)?.thumbnail(of: layout.itemSize, for: .cropBox)
        }
        
        return cell
    }

    // MARK: - Table view delegate

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
}
