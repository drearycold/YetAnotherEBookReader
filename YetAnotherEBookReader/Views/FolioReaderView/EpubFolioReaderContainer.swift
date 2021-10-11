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
    
    var yabrFolioReaderPageDelegate: YabrFolioReaderPageDelegate!
    
    var folioReaderPreferenceProvider: FolioReaderPreferenceProvider?
    var folioReaderHighlightProvider: FolioReaderHighlightProvider?

    func open(bookReadingPosition: BookDeviceReadingPosition) {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        //if bookReadingPosition.lastProgress > 0 {
            var position = [String: Any]()
            position["pageNumber"] = bookReadingPosition.lastPosition[0]
            position["pageOffsetX"] = CGFloat(bookReadingPosition.lastPosition[1])
            position["pageOffsetY"] = CGFloat(bookReadingPosition.lastPosition[2])
            readerConfig.savedPositionForCurrentBook = position
        //}
        
        self.yabrFolioReaderPageDelegate = YabrFolioReaderPageDelegate(readerConfig: self.readerConfig)
        self.folioReader.delegate = self
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willResignActiveNotification, object: nil)
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willTerminateNotification, object: nil)
        
        super.initialization()
    }

    override func viewDidDisappear(_ animated: Bool) {
        //updateReadingPosition(self.folioReader)
        
        super.viewDidDisappear(animated)
    }
    
    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        folioReader.readerCenter?.delegate = MyFolioReaderCenterDelegate()
        folioReader.readerCenter?.pageDelegate = yabrFolioReaderPageDelegate
    }
    
    func folioReaderDidClose(_ folioReader: FolioReader) {
        updateReadingPosition(folioReader)
    }
    
    func updateReadingPosition(_ folioReader: FolioReader) {
        guard var updatedReadingPosition = modelData?.updatedReadingPosition else { return }
        
        guard let chapterProgress = folioReader.readerCenter?.getCurrentPageProgress(),
           let bookProgress = folioReader.readerCenter?.getBookProgress(),
           let savedPosition = folioReader.savedPositionForCurrentBook
        else {
            return
        }
        
        if let currentChapterName = folioReader.readerCenter?.getCurrentChapterName() {
            updatedReadingPosition.lastReadChapter = currentChapterName
        } else {
            updatedReadingPosition.lastReadChapter = "Untitled Chapter"
        }
        
        updatedReadingPosition.lastChapterProgress = chapterProgress
        updatedReadingPosition.lastProgress = bookProgress
        
        guard let pageNumber = savedPosition["pageNumber"] as? Int,
              let pageOffsetX = savedPosition["pageOffsetX"] as? CGFloat,
              let pageOffsetY = savedPosition["pageOffsetY"] as? CGFloat
        else {
            return
        }
        
        updatedReadingPosition.lastPosition[0] = pageNumber
        updatedReadingPosition.lastPosition[1] = Int(pageOffsetX.rounded())
        updatedReadingPosition.lastPosition[2] = Int(pageOffsetY.rounded())
        updatedReadingPosition.lastReadPage = pageNumber
        
        if let cfi = savedPosition["cfi"] as? String {
            updatedReadingPosition.cfi = cfi
        }
        
        updatedReadingPosition.readerName = ReaderType.YabrEPUB.rawValue
        
        modelData?.updatedReadingPosition = updatedReadingPosition
    }

}

