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
class EpubReaderContainer: FolioReaderContainer {
    var myFolioReaderCenterDelegate = MyFolioReaderCenterDelegate()
    var savedPositionObserver: NSKeyValueObservation?
    var bookDetailView: BookDetailView?

    func open() {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        let bookReadingPosition = bookDetailView?.getSelectedReadingPosition()
        if( bookReadingPosition != nil ) {
            var position = [String: Any]()
            position["pageNumber"] = bookReadingPosition!.lastPosition[0]
            position["pageOffsetX"] = CGFloat(bookReadingPosition!.lastPosition[1])
            position["pageOffsetY"] = CGFloat(bookReadingPosition!.lastPosition[2])
            readerConfig.savedPositionForCurrentBook = position
        }
        
        savedPositionObserver = folioReader.observe(\.savedPositionForCurrentBook, options: .new) { reader, change in
            guard let position = change.newValue else { return }
            self.bookDetailView?.updateCurrentPosition(position)
        }
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willResignActiveNotification, object: nil)
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willTerminateNotification, object: nil)
        
        super.initialization()
    }

    override func viewDidDisappear(_ animated: Bool) {
        savedPositionObserver?.invalidate()
        savedPositionObserver = nil
    }
    
    
}
