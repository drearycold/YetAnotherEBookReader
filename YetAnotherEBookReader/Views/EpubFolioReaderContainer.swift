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
class EpubFolioReaderContainer: FolioReaderContainer, FolioReaderDelegate {
//    var savedPositionObserver: NSKeyValueObservation?
    var modelData: ModelData?
    var updatedReadingPosition = (Double(), Double(), [String: Any](), "")
    
    func open() {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        if let bookReadingPosition = modelData?.getSelectedReadingPosition() {
            var position = [String: Any]()
            position["pageNumber"] = bookReadingPosition.lastPosition[0]
            position["pageOffsetX"] = CGFloat(bookReadingPosition.lastPosition[1])
            position["pageOffsetY"] = CGFloat(bookReadingPosition.lastPosition[2])
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
        if let chapterProgress = folioReader.readerCenter?.getCurrentPageProgress(),
           let bookProgress = folioReader.readerCenter?.getBookProgress() {
            updatedReadingPosition.0 = chapterProgress
            updatedReadingPosition.1 = bookProgress
            updatedReadingPosition.2 = folioReader.savedPositionForCurrentBook!
            if let currentChapterName = folioReader.readerCenter?.getCurrentChapterName() {
                updatedReadingPosition.3 = currentChapterName
            }
            
            modelData?.updatedReadingPosition.lastChapterProgress = updatedReadingPosition.0
            modelData?.updatedReadingPosition.lastProgress = updatedReadingPosition.1
            
            modelData?.updatedReadingPosition.lastPosition[0] = updatedReadingPosition.2["pageNumber"]! as! Int
            modelData?.updatedReadingPosition.lastPosition[1] = Int((updatedReadingPosition.2["pageOffsetX"]! as! CGFloat).rounded())
            modelData?.updatedReadingPosition.lastPosition[2] = Int((updatedReadingPosition.2["pageOffsetY"]! as! CGFloat).rounded())
            modelData?.updatedReadingPosition.lastReadPage = updatedReadingPosition.2["pageNumber"]! as! Int
            
            modelData?.updatedReadingPosition.lastReadChapter = updatedReadingPosition.3
            
            modelData?.updatedReadingPosition.readerName = "FolioReader"
        }
    }
}
