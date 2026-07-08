//
//  YabrEBookReaderNavigationController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/12/5.
//

import Foundation
import UIKit
import SwiftUI

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
    
    var container: AppContainer
    
    let book: CalibreBook
    let readerInfo: ReaderInfo
    let presentationID: ReaderPresentation.ID?
    let lifecycleEvents: () -> AsyncStream<ScenePhase>
    
    private var activityTask: Task<Void, Never>?
    private var currentSessionHandle: ReadingSessionHandle?
    
    init(
        container: AppContainer,
        book: CalibreBook,
        readerInfo: ReaderInfo,
        presentationID: ReaderPresentation.ID?,
        lifecycleEvents: @escaping () -> AsyncStream<ScenePhase>
    ) {
        self.container = container
        self.book = book
        self.readerInfo = readerInfo
        self.presentationID = presentationID
        self.lifecycleEvents = lifecycleEvents
        
        super.init(navigationBarClass: nil, toolbarClass: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func alert(alertItem: AlertItem) {
        // pass
    }
    
    override func viewWillAppear(_ animated: Bool) {
        currentSessionHandle = container.readingPositionRepository.beginSession(at: readerInfo.position, for: book)
        activityTask?.cancel()
        let activities = lifecycleEvents()
        activityTask = Task { @MainActor [weak self] in
            for await activity in activities {
                guard !Task.isCancelled else { return }
                self?.handleBookReaderActivity(activity)
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        activityTask?.cancel()
        activityTask = nil
        
        if let position = self.container.readingPositionRepository.getPosition(for: self.book, policy: .latestForDevice(self.container.deviceName)),
           let handle = currentSessionHandle {
            container.readingPositionRepository.endSession(handle, at: position, for: book)
            currentSessionHandle = nil
        }
        
        if container.consumeReaderPresentationTransfer(id: presentationID) == false {
            let bookToClose = book
            let positionAtClose = readerInfo.position

            Task {
                await self.container.sessionManager.onBookReaderClosed(book: bookToClose, lastPosition: positionAtClose)
            }
        }
    }

    private func handleBookReaderActivity(_ activity: ScenePhase) {
        switch activity {
        case .background:
            let handleToEnd = currentSessionHandle
            switch readerInfo.readerType {
            case .YabrEPUB:
                guard let yabrEPub: EpubFolioReaderContainer = findChildViewController() else { break }
                yabrEPub.folioReader.saveReaderState {
                    if let position = self.container.readingPositionRepository.getPosition(for: self.book, policy: .latestForDevice(self.container.deviceName)),
                       let handle = handleToEnd {
                        self.container.readingPositionRepository.endSession(handle, at: position, for: self.book)
                    }
                }
            case .YabrPDF:
                guard let yabrPDF: YabrPDFViewController = findChildViewController() else { break }
                yabrPDF.updatePageViewPositionHistory()
                yabrPDF.updateReadingProgress()
                if let position = container.readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container.deviceName)),
                   let handle = handleToEnd {
                    container.readingPositionRepository.endSession(handle, at: position, for: book)
                }
            case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
                guard let yabrReadium: YabrReadiumReaderViewController = findChildViewController(),
                      let locator = yabrReadium.navigator.currentLocation
                else { break }
                yabrReadium.navigator(yabrReadium.navigator, locationDidChange: locator)
                if let position = container.readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container.deviceName)),
                   let handle = handleToEnd {
                    container.readingPositionRepository.endSession(handle, at: position, for: book)
                }
            case .UNSUPPORTED:
                break
            }
        case .inactive:
            break
        case .active:
            if let position = container.readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container.deviceName)),
               position.readerName == readerInfo.readerType.rawValue {
                currentSessionHandle = container.readingPositionRepository.beginSession(at: position, for: book)
            }
        @unknown default:
            break
        }
    }
}
