//
//  YabrEBookReaderNavigationController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/12/5.
//

import Foundation
import UIKit
import Combine

class YabrEBookReaderNavigationController: UINavigationController, AlertDelegate {
    var modelData: ModelData
    
    let book: CalibreBook
    let readerInfo: ReaderInfo
    
    var activityCancellables = Set<AnyCancellable>()
    
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
        
        modelData.bookReaderActivitySubject.sink { subject in
            switch subject {
            case .background:
                switch self.readerInfo.readerType {
                case .YabrEPUB:
                    guard let yabrEPub: EpubFolioReaderContainer = self.findChildViewController() else { break }
                    yabrEPub.folioReader.saveReaderState {
                        yabrEPub.updateReadingPosition(yabrEPub.folioReader)
                        if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
                            self.book.readPos.session(end: position)
                        }
                    }
                case .YabrPDF:
                    guard let yabrPDF: YabrPDFViewController = self.findChildViewController() else { break }
                    yabrPDF.updatePageViewPositionHistory()
                    yabrPDF.updateReadingProgress()
                    if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
                        self.book.readPos.session(end: position)
                    }
                case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
                    guard let yabrReadium: YabrReadiumReaderViewController = self.findChildViewController(),
                          let locator = yabrReadium.navigator.currentLocation
                    else { break }
                    yabrReadium.navigator(yabrReadium.navigator, locationDidChange: locator)
                    if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
                        self.book.readPos.session(end: position)
                    }
                case .UNSUPPORTED:
                    break
                }
            case .inactive:
                break   //trans, do nothing
            case .active:
                if let position = self.book.readPos.getPosition(self.modelData.deviceName),
                   position.readerName == self.readerInfo.readerType.rawValue {
                    self.book.readPos.session(start: position)
                }
            @unknown default:
                break
            }
        }.store(in: &activityCancellables)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        activityCancellables.removeAll()
        
        if let position = self.book.readPos.getPosition(self.modelData.deviceName) {
            self.book.readPos.session(end: position)
        }
        
        ModelData.shared?.bookReaderClosedSubject.send((book: book, position: readerInfo.position))
    }
}
