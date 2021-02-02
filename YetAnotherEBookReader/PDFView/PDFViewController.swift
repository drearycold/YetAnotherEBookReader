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

    func open(pdfURL: URL, bookDetailView: BookDetailView) {
        self.bookDetailView = bookDetailView
        
        pdfView = PDFView()
        
        pdfView!.displayMode = PDFDisplayMode.singlePage
        pdfView!.displayDirection = PDFDisplayDirection.horizontal
        pdfView!.interpolationQuality = PDFInterpolationQuality.high
        
        pdfView!.usePageViewController(true, withViewOptions: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageChange(notification:)), name: .PDFViewPageChanged, object: pdfView!)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScaleChange(_:)), name: .PDFViewScaleChanged, object: nil)
        
        logger.info("pdfURL: \(pdfURL.absoluteString)")
        logger.info("Exist: \(FileManager.default.fileExists(atPath: pdfURL.path))")
        
        let pdfDoc = PDFDocument(url: pdfURL)
        pdfDoc?.delegate = self
        logger.info("pdfDoc: \(pdfDoc?.majorVersion ?? -1) \(pdfDoc?.minorVersion ?? -1)")
        
        pdfView!.document = pdfDoc
        pdfView!.autoScales = true
                
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
        }
    }
    
    func classForPage() -> AnyClass {
        return PDFPageWithBackground.self
    }
    
    @objc private func handlePageChange(notification: Notification)
    {
        
        // pdfView!.scaleFactor = lastScale
    }
    
    @objc func handleScaleChange(_ sender: Any?)
    {
        self.lastScale = pdfView!.scaleFactor
    }
}
