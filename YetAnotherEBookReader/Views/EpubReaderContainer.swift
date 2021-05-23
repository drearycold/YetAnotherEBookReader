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
class EpubReaderContainer: FolioReaderContainer, FolioReaderDelegate {
//    var savedPositionObserver: NSKeyValueObservation?
    var modelData: ModelData?
    var updatedReadingPosition = (Double(), [String: Any](), "")
    
    func open() {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        let bookReadingPosition = modelData?.getSelectedReadingPosition()
        if( bookReadingPosition != nil ) {
            var position = [String: Any]()
            position["pageNumber"] = bookReadingPosition!.lastPosition[0]
            position["pageOffsetX"] = CGFloat(bookReadingPosition!.lastPosition[1])
            position["pageOffsetY"] = CGFloat(bookReadingPosition!.lastPosition[2])
            readerConfig.savedPositionForCurrentBook = position
        }
        
        self.folioReader.delegate = self
        
//        savedPositionObserver = folioReader.observe(\.savedPositionForCurrentBook, options: .new) { [self] reader, change in
//            if let bookProgress = reader.readerCenter?.getBookProgress(), let newValue = change.newValue, let position = newValue {
//                updatedReadingPosition.0 = bookProgress
//                updatedReadingPosition.1 = position
//                if let currentChapterName = reader.readerCenter?.getCurrentChapterName() {
//                    updatedReadingPosition.2 = currentChapterName
//                }
//            }
//        }
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willResignActiveNotification, object: nil)
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willTerminateNotification, object: nil)
        
        super.initialization()
    }

//    override func viewDidDisappear(_ animated: Bool) {
////        savedPositionObserver?.invalidate()
////        savedPositionObserver = nil
//        //self.modelData?.updateCurrentPosition(progress: bookProgress, position: position)
//        
//        // folioReader.close()
//        
//        
//        
//        super.viewDidDisappear(animated)
//    }
    
    func folioReaderDidClose(_ folioReader: FolioReader) {
        if let bookProgress = folioReader.readerCenter?.getBookProgress() {
            updatedReadingPosition.0 = bookProgress
            updatedReadingPosition.1 = folioReader.savedPositionForCurrentBook!
            if let currentChapterName = folioReader.readerCenter?.getCurrentChapterName() {
                updatedReadingPosition.2 = currentChapterName
            }
            
            modelData?.updatedReadingPosition.lastPosition[0] = updatedReadingPosition.1["pageNumber"]! as! Int
            modelData?.updatedReadingPosition.lastPosition[1] = Int((updatedReadingPosition.1["pageOffsetX"]! as! CGFloat).rounded())
            modelData?.updatedReadingPosition.lastPosition[2] = Int((updatedReadingPosition.1["pageOffsetY"]! as! CGFloat).rounded())
            modelData?.updatedReadingPosition.lastReadPage = updatedReadingPosition.1["pageNumber"]! as! Int
            modelData?.updatedReadingPosition.lastProgress = updatedReadingPosition.0
            modelData?.updatedReadingPosition.lastReadChapter = updatedReadingPosition.2
            modelData?.updatedReadingPosition.readerName = "FolioReader"
        }
    }
}
