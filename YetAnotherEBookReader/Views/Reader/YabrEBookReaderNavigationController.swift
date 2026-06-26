//
//  YabrEBookReaderNavigationController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/12/5.
//

import Foundation
import UIKit
import Combine

extension UIViewController {
    /// Finds the first child view controller with the given type, recursively.
    func findChildViewController<T: UIViewController>() -> T? {
        for childViewController in children {
            if let found = childViewController as? T {
                return found
            }
            if let found: T = childViewController.findChildViewController() {
                return found
            }
        }
        return nil
    }
}

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
        modelData.readingPositionRepository.session(start: readerInfo.position, forBookId: book.bookPrefId)
        
        modelData.bookReaderActivitySubject.sink { subject in
            switch subject {
            case .background:
                switch self.readerInfo.readerType {
                case .YabrEPUB:
                    guard let yabrEPub: EpubFolioReaderContainer = self.findChildViewController() else { break }
                    yabrEPub.folioReader.saveReaderState {
                        if let position = self.modelData.readingPositionRepository.getPosition(forBookId: self.book.bookPrefId, deviceName: self.modelData.deviceName) {
                            self.modelData.readingPositionRepository.session(end: position, forBookId: self.book.bookPrefId)
                        }
                    }
                case .YabrPDF:
                    guard let yabrPDF: YabrPDFViewController = self.findChildViewController() else { break }
                    yabrPDF.updatePageViewPositionHistory()
                    yabrPDF.updateReadingProgress()
                    if let position = self.modelData.readingPositionRepository.getPosition(forBookId: self.book.bookPrefId, deviceName: self.modelData.deviceName) {
                        self.modelData.readingPositionRepository.session(end: position, forBookId: self.book.bookPrefId)
                    }
                case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
                    guard let yabrReadium: YabrReadiumReaderViewController = self.findChildViewController(),
                          let locator = yabrReadium.navigator.currentLocation
                    else { break }
                    yabrReadium.navigator(yabrReadium.navigator, locationDidChange: locator)
                    if let position = self.modelData.readingPositionRepository.getPosition(forBookId: self.book.bookPrefId, deviceName: self.modelData.deviceName) {
                        self.modelData.readingPositionRepository.session(end: position, forBookId: self.book.bookPrefId)
                    }
                case .UNSUPPORTED:
                    break
                }
            case .inactive:
                break   //trans, do nothing
            case .active:
                if let position = self.modelData.readingPositionRepository.getPosition(forBookId: self.book.bookPrefId, deviceName: self.modelData.deviceName),
                   position.readerName == self.readerInfo.readerType.rawValue {
                    self.modelData.readingPositionRepository.session(start: position, forBookId: self.book.bookPrefId)
                }
            @unknown default:
                break
            }
        }.store(in: &activityCancellables)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        activityCancellables.removeAll()
        
        if let position = self.modelData.readingPositionRepository.getPosition(forBookId: self.book.bookPrefId, deviceName: self.modelData.deviceName) {
            self.modelData.readingPositionRepository.session(end: position, forBookId: self.book.bookPrefId)
        }
        
        let bookToClose = book
        let positionAtClose = readerInfo.position
        
        Task {
            await self.modelData.sessionManager.onBookReaderClosed(book: bookToClose, lastPosition: positionAtClose)
        }
    }
}
