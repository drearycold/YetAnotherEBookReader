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
    
    var yabrFolioReaderPageDelegate: YabrFolioReaderPageDelegate!
    
    func open(bookReadingPosition: BookDeviceReadingPosition) {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        if bookReadingPosition.lastProgress > 0 {
            var position = [String: Any]()
            position["pageNumber"] = bookReadingPosition.lastPosition[0]
            position["pageOffsetX"] = CGFloat(bookReadingPosition.lastPosition[1])
            position["pageOffsetY"] = CGFloat(bookReadingPosition.lastPosition[2])
            readerConfig.savedPositionForCurrentBook = position
        }
        
        self.yabrFolioReaderPageDelegate = YabrFolioReaderPageDelegate(readerConfig: self.readerConfig)
        self.folioReader.delegate = self
        
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
    
    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        folioReader.readerCenter?.delegate = MyFolioReaderCenterDelegate()
        folioReader.readerCenter?.pageDelegate = yabrFolioReaderPageDelegate
    }
    
    func folioReaderDidClose(_ folioReader: FolioReader) {
        guard let chapterProgress = folioReader.readerCenter?.getCurrentPageProgress(),
           let bookProgress = folioReader.readerCenter?.getBookProgress() else {
            return
        }
        
        if let currentChapterName = folioReader.readerCenter?.getCurrentChapterName() {
            modelData?.updatedReadingPosition.lastReadChapter = currentChapterName
        }
        
        modelData?.updatedReadingPosition.lastChapterProgress = chapterProgress
        modelData?.updatedReadingPosition.lastProgress = bookProgress
        
        modelData?.updatedReadingPosition.lastPosition[0] = folioReader.savedPositionForCurrentBook!["pageNumber"]! as! Int
        modelData?.updatedReadingPosition.lastPosition[1] = Int((folioReader.savedPositionForCurrentBook!["pageOffsetX"]! as! CGFloat).rounded())
        modelData?.updatedReadingPosition.lastPosition[2] = Int((folioReader.savedPositionForCurrentBook!["pageOffsetY"]! as! CGFloat).rounded())
        modelData?.updatedReadingPosition.lastReadPage = folioReader.savedPositionForCurrentBook!["pageNumber"]! as! Int
        
        modelData?.updatedReadingPosition.readerName = "FolioReader"
    }
    

}
