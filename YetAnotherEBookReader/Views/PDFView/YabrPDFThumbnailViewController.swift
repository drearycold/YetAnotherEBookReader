//
//  YabrPDFThumbnailViewController.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/13.
//

import Foundation
import UIKit
import PDFKit

class YabrPDFThumbnailViewController : UIViewController {
    var pdfView: PDFView!
    
    let pdfThumbnailView = PDFThumbnailView()
    let pdfThumbnailViewScroll = UIScrollView()
    
    override func viewDidLoad() {
        let pdfView = PDFView()
        if let documentURL = self.pdfView.document?.documentURL {
            pdfView.document = PDFDocument(url: documentURL)
        }
        pdfView.delegate = self
        
        pdfThumbnailView.pdfView = pdfView
        
        pdfThumbnailView.thumbnailSize = .init(width: 300, height: 400)
        pdfThumbnailView.translatesAutoresizingMaskIntoConstraints = false
        pdfThumbnailView.contentInset = .init(top: 10, left: 10, bottom: 10, right: 10)
        
        pdfThumbnailViewScroll.addSubview(pdfThumbnailView)
        NSLayoutConstraint.activate([
            pdfThumbnailView.widthAnchor.constraint(equalToConstant: pdfThumbnailView.thumbnailSize.width),
            pdfThumbnailView.heightAnchor.constraint(equalToConstant: pdfThumbnailView.thumbnailSize.height * CGFloat(self.pdfView.document?.pageCount ?? 0)),
            pdfThumbnailView.centerXAnchor.constraint(equalTo: pdfThumbnailViewScroll.centerXAnchor)
        ])
        
        pdfThumbnailViewScroll.translatesAutoresizingMaskIntoConstraints = false
        pdfThumbnailViewScroll.layer.borderColor = UIColor.yellow.cgColor
        pdfThumbnailViewScroll.layer.borderWidth = 4
        pdfThumbnailViewScroll.isScrollEnabled = true
        pdfThumbnailViewScroll.showsVerticalScrollIndicator = true
        pdfThumbnailViewScroll.backgroundColor = self.pdfView.backgroundColor
        pdfThumbnailViewScroll.contentSize = .init(width: pdfThumbnailView.thumbnailSize.width, height: pdfThumbnailView.thumbnailSize.height * CGFloat(self.pdfView.document?.pageCount ?? 0))
        
        self.view.addSubview(pdfThumbnailViewScroll)
        
        NSLayoutConstraint.activate([
            pdfThumbnailViewScroll.topAnchor.constraint(equalTo: self.view.topAnchor),
            pdfThumbnailViewScroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            pdfThumbnailViewScroll.heightAnchor.constraint(equalTo: self.view.heightAnchor),
            pdfThumbnailViewScroll.widthAnchor.constraint(equalTo: self.view.widthAnchor)
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if let pageNumber = self.pdfView.currentPage?.pageRef?.pageNumber {
            pdfThumbnailViewScroll.setContentOffset(
                .init(x: 0, y: CGFloat(pageNumber) * self.pdfThumbnailView.thumbnailSize.height - self.view.frame.height / 2),
                animated: false
            )
        }
    }
}

extension YabrPDFThumbnailViewController: PDFViewDelegate {
    func pdfViewPerformGo(toPage sender: PDFView) {
        print("\(#function) sender=\(sender)")
    }
}
