//
//  ViewController.swift
//  Example
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioReaderKit

@available(macCatalyst 14.0, *)
class FolioReaderViewController: UIViewController {
    var folioReader: FolioReader?
    var myFolioReaderCenterDelegate = MyFolioReaderCenterDelegate()
    var savedPositionObserver: NSKeyValueObservation?
    var bookDetailView: BookDetailView?

    private func readerConfiguration() -> FolioReaderConfig {
        let config = FolioReaderConfig(withIdentifier: "READER")
        config.shouldHideNavigationOnTap = false
        config.scrollDirection = FolioReaderScrollDirection.vertical
        
        // Custom sharing quote background
        config.quoteCustomBackgrounds = []
        if let image = UIImage(named: "demo-bg") {
            let customImageQuote = QuoteImage(withImage: image, alpha: 0.6, backgroundColor: UIColor.black)
            config.quoteCustomBackgrounds.append(customImageQuote)
        }

        let textColor = UIColor(red:0.86, green:0.73, blue:0.70, alpha:1.0)
        let customColor = UIColor(red:0.30, green:0.26, blue:0.20, alpha:1.0)
        let customQuote = QuoteImage(withColor: customColor, alpha: 1.0, textColor: textColor)
        config.quoteCustomBackgrounds.append(customQuote)

        return config
    }

    func open(epubURL: URL) {
        let bookPath = epubURL.path
        let readerConfiguration = self.readerConfiguration()
        readerConfiguration.loadSavedPositionForCurrentBook = true
        
        let bookReadingPosition = bookDetailView?.book.readPos.getPosition(UIDevice().name)
        if( bookReadingPosition != nil ) {
            var position = [String: Any]()
            position["pageNumber"] = bookReadingPosition!.lastPosition[0]
            position["pageOffsetX"] = CGFloat(bookReadingPosition!.lastPosition[1])
            position["pageOffsetY"] = CGFloat(bookReadingPosition!.lastPosition[2])
            readerConfiguration.savedPositionForCurrentBook = position
        }
        
        savedPositionObserver = folioReader?.observe(\.savedPositionForCurrentBook, options: .new) { reader, change in
            guard let position = change.newValue else { return }
            self.bookDetailView?.updateCurrentPosition(position)
        }
        
        folioReader?.presentReader(parentViewController: self, withEpubPath: bookPath, andConfig: readerConfiguration, shouldRemoveEpub: false, folioReaderCenterDelegate: myFolioReaderCenterDelegate)
    }

    override func viewDidDisappear(_ animated: Bool) {
        savedPositionObserver?.invalidate()
        savedPositionObserver = nil
    }
    
    
}

class MyFolioReaderCenterDelegate: FolioReaderCenterDelegate {
    
    @objc func htmlContentForPage(_ page: FolioReaderPage, htmlContent: String) -> String {
        
        // print(htmlContent)
        let regex = try! NSRegularExpression(pattern: "background=\"[^\"]+\"", options: .caseInsensitive)
        
        
        let modified = regex.stringByReplacingMatches(in: htmlContent, options: [], range: NSMakeRange(0, htmlContent.count), withTemplate: "").replacingOccurrences(of: "<body ", with: "<body style=\"text-align: justify !important; display: block !important; \" ")
        print(modified)
        return modified
    }
}
