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
    
    override func viewWillAppear(_ animated: Bool) {
        book.readPos.session(start: readerInfo.position)
        
        modelData.bookReaderEnterBackgroundCancellable?.cancel()
        modelData.bookReaderEnterBackgroundCancellable = modelData.bookReaderEnterBackgroundPublished.sink { _ in
            switch self.readerInfo.readerType {
            case .YabrEPUB:
                if let yabrEPub: EpubFolioReaderContainer = self.findChildViewController() {
                    yabrEPub.folioReader.saveReaderState {
                        yabrEPub.updateReadingPosition(yabrEPub.folioReader)
                        if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
                            self.book.readPos.session(end: position)
                        }
                    }
                }
            case .YabrPDF:
                if let yabrPDF: YabrPDFViewController = self.findChildViewController() {
                    yabrPDF.updatePageViewPositionHistory()
                    yabrPDF.updateReadingProgress()
                    if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
                        self.book.readPos.session(end: position)
                    }
                }
            case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
                if let yabrReadium: YabrReadiumReaderViewController = self.findChildViewController(),
                   let locator = yabrReadium.navigator.currentLocation {
                    yabrReadium.navigator(yabrReadium.navigator, locationDidChange: locator)
                    if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
                        self.book.readPos.session(end: position)
                    }
                }
            case .UNSUPPORTED:
                break
            }
        }
        
        modelData.bookReaderEnterActiveCancellable?.cancel()
        modelData.bookReaderEnterActiveCancellable = modelData.bookReaderEnterActivePublished.sink { _ in
            if let position = self.book.readPos.getPosition(self.modelData.deviceName),
               position.readerName == self.readerInfo.readerType.rawValue {
                self.book.readPos.session(start: position)
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        ModelData.shared?.bookReaderEnterBackgroundCancellable?.cancel()
        ModelData.shared?.bookReaderEnterBackgroundCancellable = nil
        ModelData.shared?.bookReaderEnterActiveCancellable?.cancel()
        ModelData.shared?.bookReaderEnterActiveCancellable = nil
        
        if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
            self.book.readPos.session(end: position)
        }
        
        NotificationCenter.default.post(
            name: .YABR_BookReaderClosed,
            object: book.inShelfId,
            userInfo: ["lastPosition": readerInfo.position]
        )
    }
}
