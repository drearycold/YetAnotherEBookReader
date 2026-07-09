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
    let lifecycleEvents: () -> AsyncStream<ReaderPresentationLifecycleEvent>
    
    private var activityTask: Task<Void, Never>?
    private var currentSessionHandle: ReadingSessionHandle?
    private var isPresentationActive = false
    private var pendingUnmountReason: ReaderPresentationUnmountReason?
    
    init(
        container: AppContainer,
        book: CalibreBook,
        readerInfo: ReaderInfo,
        presentationID: ReaderPresentation.ID?,
        lifecycleEvents: @escaping () -> AsyncStream<ReaderPresentationLifecycleEvent>
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
        activityTask?.cancel()
        let activities = lifecycleEvents()
        activityTask = Task { @MainActor [weak self] in
            for await activity in activities {
                guard !Task.isCancelled else { return }
                self?.handleReaderLifecycleEvent(activity)
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        activityTask?.cancel()
        activityTask = nil

        flushCurrentPositionAndEndSession()

        let shouldHandleClose = pendingUnmountReason == .close ||
            (pendingUnmountReason == nil && container.consumeReaderPresentationTransfer(id: presentationID) == false)

        if shouldHandleClose {
            let bookToClose = book
            let positionAtClose = readerInfo.position

            Task {
                await self.container.sessionManager.onBookReaderClosed(book: bookToClose, lastPosition: positionAtClose)
            }
        } else if pendingUnmountReason == .transfer {
            _ = container.consumeReaderPresentationTransfer(id: presentationID)
        }
    }

    private func handleReaderLifecycleEvent(_ event: ReaderPresentationLifecycleEvent) {
        switch event {
        case .activated:
            isPresentationActive = true
            beginCurrentSession()
        case .deactivated:
            isPresentationActive = false
            flushCurrentPositionAndEndSession()
        case let .scenePhase(scenePhase):
            handleScenePhase(scenePhase)
        case let .unmount(reason):
            pendingUnmountReason = reason
            isPresentationActive = false
            flushCurrentPositionAndEndSession()
        }
    }

    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            flushCurrentPositionAndEndSession()
        case .inactive:
            break
        case .active:
            if isPresentationActive {
                beginCurrentSession()
            }
        @unknown default:
            break
        }
    }

    private func beginCurrentSession() {
        guard currentSessionHandle == nil else { return }
        let position = container.readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container.deviceName)) ?? readerInfo.position
        guard position.readerName == readerInfo.readerType.rawValue else { return }
        currentSessionHandle = container.readingPositionRepository.beginSession(at: position, for: book)
    }

    private func flushCurrentPositionAndEndSession() {
        switch readerInfo.readerType {
        case .YabrEPUB:
            guard let yabrEPub: EpubFolioReaderContainer = findChildViewController() else {
                endCurrentSessionAtLatestPosition()
                return
            }
            let handleToEnd = currentSessionHandle
            currentSessionHandle = nil
            yabrEPub.folioReader.saveReaderState {
                if let position = self.container.readingPositionRepository.getPosition(for: self.book, policy: .latestForDevice(self.container.deviceName)),
                   position.readerName == self.readerInfo.readerType.rawValue,
                   let handle = handleToEnd {
                    self.container.sessionManager.recordReaderPresentationPosition(id: self.presentationID, position: position)
                    self.container.readingPositionRepository.endSession(handle, at: position, for: self.book)
                }
            }
        case .YabrPDF:
            guard let yabrPDF: YabrPDFViewController = findChildViewController() else {
                endCurrentSessionAtLatestPosition()
                return
            }
            yabrPDF.updatePageViewPositionHistory()
            yabrPDF.updateReadingProgress()
            endCurrentSessionAtLatestPosition()
        case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
            guard let yabrReadium: YabrReadiumReaderViewController = findChildViewController(),
                  let locator = yabrReadium.navigator.currentLocation
            else {
                endCurrentSessionAtLatestPosition()
                return
            }
            yabrReadium.navigator(yabrReadium.navigator, locationDidChange: locator)
            endCurrentSessionAtLatestPosition()
        case .UNSUPPORTED:
            endCurrentSessionAtLatestPosition()
        }
    }

    private func endCurrentSessionAtLatestPosition() {
        guard let handle = currentSessionHandle else { return }
        currentSessionHandle = nil
        guard let position = container.readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container.deviceName)),
              position.readerName == readerInfo.readerType.rawValue else {
            return
        }
        container.sessionManager.recordReaderPresentationPosition(id: presentationID, position: position)
        container.readingPositionRepository.endSession(handle, at: position, for: book)
    }
}
