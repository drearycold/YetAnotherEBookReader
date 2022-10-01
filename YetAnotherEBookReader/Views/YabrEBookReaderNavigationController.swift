//
//  YabrEBookReaderNavigationController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/12/5.
//

import Foundation
import UIKit

class YabrEBookReaderNavigationController: UINavigationController, AlertDelegate {
    var modelData: ModelData
    
    let book: CalibreBook
    let readerInfo: ReaderInfo
    
    init(modelData: ModelData, book: CalibreBook, readerInfo: ReaderInfo) {
        self.modelData = modelData
        self.book = book
        self.readerInfo = readerInfo
        
        super.init(navigationBarClass: nil, toolbarClass: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func alert(alertItem: AlertItem) {
        // pass
    }
    
    func saveUpdatedReadingPosition() {
        /*
        guard let modelData = ModelData.shared else { return }

        guard let book = modelData.readingBook, let readerInfo = modelData.readerInfo else { return }
        
        let updatedReadingPosition = modelData.updatedReadingPosition
        let originalPosition = readerInfo.position
        guard updatedReadingPosition.isSameType(with: originalPosition),
              updatedReadingPosition.isSameProgress(with: originalPosition) == false else { return }
        
        modelData.logBookDeviceReadingPositionHistoryFinish(book: book, endPosition: updatedReadingPosition)
        modelData.updateCurrentPosition(alertDelegate: self)
        */
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        modelData.bookReaderEnterBackgroundCancellable?.cancel()
        modelData.bookReaderEnterBackgroundCancellable = modelData.bookReaderEnterBackgroundPublished.sink { _ in
            switch self.readerInfo.readerType {
            case .YabrEPUB:
                if let yabrEPub: EpubFolioReaderContainer = self.findChildViewController() {
                    yabrEPub.folioReader.saveReaderState {
                        yabrEPub.updateReadingPosition(yabrEPub.folioReader)
                        self.saveUpdatedReadingPosition()
                        if let bookId = yabrEPub.folioReader.readerConfig?.identifier,
                           let delegate = yabrEPub.folioReader.delegate?.folioReaderReadPositionProvider?(yabrEPub.folioReader),
                           let position = yabrEPub.folioReader.savedPositionForCurrentBook {
                            delegate.folioReaderPositionHistory?(yabrEPub.folioReader, bookId: bookId, finish: position)
                        }
                    }
                }
            case .YabrPDF:
                if let yabrPDF: YabrPDFViewController = self.findChildViewController() {
                    yabrPDF.updateReadingProgress()
                    self.saveUpdatedReadingPosition()
                }
            case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
                if let yabrReadium: YabrReadiumReaderViewController = self.findChildViewController() {
                    self.modelData.updatedReadingPosition = yabrReadium.getUpdateReadingPosition(position: self.modelData.updatedReadingPosition)
                    self.saveUpdatedReadingPosition()
                }
            case .UNSUPPORTED:
                break
            }
        }
        
        modelData.bookReaderEnterActiveCancellable?.cancel()
        modelData.bookReaderEnterActiveCancellable = modelData.bookReaderEnterActivePublished.sink { _ in
//            modelData.logBookDeviceReadingPositionHistoryStart(book: book, position: modelData.updatedReadingPosition, startDatetime: Date())
            
            if let yabrEPub: EpubFolioReaderContainer = self.findChildViewController() {
                if let bookId = yabrEPub.folioReader.readerConfig?.identifier,
                   let delegate = yabrEPub.folioReader.delegate?.folioReaderReadPositionProvider?(yabrEPub.folioReader),
                   let position = yabrEPub.folioReader.savedPositionForCurrentBook {
                    delegate.folioReaderPositionHistory?(yabrEPub.folioReader, bookId: bookId, start: position)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        ModelData.shared?.bookReaderEnterBackgroundCancellable?.cancel()
        ModelData.shared?.bookReaderEnterBackgroundCancellable = nil
        ModelData.shared?.bookReaderEnterActiveCancellable?.cancel()
        ModelData.shared?.bookReaderEnterActiveCancellable = nil
        
//        NotificationCenter.default.post(.init(name: .YABR_BookReaderClosed))
        
        guard let modelData = ModelData.shared,
              let book = modelData.readingBook,
              let readerInfo = modelData.readerInfo
        else { return }
        
        NotificationCenter.default.post(
            name: .YABR_BookReaderClosed,
            object: book.inShelfId,
            userInfo: ["lastPosition": readerInfo.position]
        )
    }
}
