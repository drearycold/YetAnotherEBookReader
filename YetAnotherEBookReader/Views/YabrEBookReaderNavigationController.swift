//
//  YabrEBookReaderNavigationController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/12/5.
//

import Foundation
import UIKit

class YabrEBookReaderNavigationController: UINavigationController, AlertDelegate {
    func alert(alertItem: AlertItem) {
        // pass
    }
    
    func saveUpdatedReadingPosition() {
        guard let modelData = ModelData.shared else { return }

        guard let book = modelData.readingBook, let readerInfo = modelData.readerInfo else { return }
        
        let updatedReadingPosition = modelData.updatedReadingPosition
        let originalPosition = readerInfo.position
        guard updatedReadingPosition.isSameProgress(with: originalPosition) == false else { return }
        
        modelData.logBookDeviceReadingPositionHistoryFinish(book: book, endPosition: updatedReadingPosition)
        modelData.updateCurrentPosition(alertDelegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        guard let modelData = ModelData.shared else { return }
        
        modelData.bookReaderEnterBackgroundCancellable?.cancel()
        modelData.bookReaderEnterBackgroundCancellable = ModelData.shared?.bookReaderEnterBackgroundPublished.sink { _ in
            if let yabrEPub: EpubFolioReaderContainer = self.findChildViewController() {
                yabrEPub.folioReader.saveReaderState {
                    yabrEPub.updateReadingPosition(yabrEPub.folioReader)
                    self.saveUpdatedReadingPosition()
                }
            }
            
            if let yabrPDF: YabrPDFViewController = self.findChildViewController() {
                yabrPDF.updateReadingProgress()
                self.saveUpdatedReadingPosition()
            }
            
            if let yabrReadium: YabrReadiumReaderViewController = self.findChildViewController() {
                modelData.updatedReadingPosition = yabrReadium.getUpdateReadingPosition(position: modelData.updatedReadingPosition)
                self.saveUpdatedReadingPosition()
            }
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        ModelData.shared?.bookReaderEnterBackgroundCancellable?.cancel()
        ModelData.shared?.bookReaderEnterBackgroundCancellable = nil
        
        NotificationCenter.default.post(.init(name: .YABR_BookReaderClosed))
    }
}