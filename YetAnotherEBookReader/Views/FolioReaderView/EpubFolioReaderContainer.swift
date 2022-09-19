//
//  ViewController.swift
//  Example
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioReaderKit
import GCDWebServer
import ZIPFoundation

internal let kGCDWebServerPreferredPort = 46436

@available(macCatalyst 14.0, *)
class EpubFolioReaderContainer: FolioReaderContainer, FolioReaderDelegate {
//    var savedPositionObserver: NSKeyValueObservation?
    var modelData: ModelData?
    
    var yabrFolioReaderPageDelegate: YabrFolioReaderPageDelegate!
    
    var folioReaderPreferenceProvider: FolioReaderPreferenceProvider?
    var folioReaderHighlightProvider: FolioReaderHighlightProvider?
    var folioReaderReadPositionProvider: FolioReaderReadPositionProvider?
    var folioReaderBookmarkProvider: FolioReaderBookmarkProvider?

    let webServer = GCDWebServer()
    let dateFormatter = DateFormatter()
    var epubArchive: Archive?

    func open(bookReadingPosition: BookDeviceReadingPosition) {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        self.yabrFolioReaderPageDelegate = YabrFolioReaderPageDelegate(readerConfig: self.readerConfig)
        self.folioReader.delegate = self
        
        let position = bookReadingPosition.managedObject().toFolioReaderReadPosition()
        
        readerConfig.savedPositionForCurrentBook = position
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willResignActiveNotification, object: nil)
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willTerminateNotification, object: nil)
        
        super.initialization()
    }

    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        folioReader.readerCenter?.delegate = MyFolioReaderCenterDelegate()
        folioReader.readerCenter?.pageDelegate = yabrFolioReaderPageDelegate
        
        self.epubArchive = book.epubArchive
        initializeWebServer()
        readerConfig.serverPort = Int(webServer.port)
        
        if let bookId = readerConfig.identifier,
           let savedPosition = readerConfig.savedPositionForCurrentBook,
           let provider = folioReader.delegate?.folioReaderReadPositionProvider?(folioReader) {
            provider.folioReaderPositionHistory?(folioReader, bookId: bookId, start: savedPosition)
        }
    }
    
    func folioReaderDidClose(_ folioReader: FolioReader) {
        updateReadingPosition(folioReader)
        webServer.stop()
        
        if let bookId = readerConfig.identifier,
           let savedPosition = folioReader.savedPositionForCurrentBook,
           let provider = folioReader.delegate?.folioReaderReadPositionProvider?(folioReader) {
            provider.folioReaderPositionHistory?(folioReader, bookId: bookId, finish: savedPosition)
        }
    }
    
    func updateReadingPosition(_ folioReader: FolioReader) {
//        guard var updatedReadingPosition = modelData?.updatedReadingPosition else { return }
        
        guard let savedPosition = folioReader.savedPositionForCurrentBook else { return }
        
//        updatedReadingPosition.lastChapterProgress = savedPosition.chapterProgress
//        updatedReadingPosition.lastProgress = savedPosition.structuralStyle == .bundle ? savedPosition.bundleProgress : savedPosition.bookProgress
//        updatedReadingPosition.lastReadChapter = savedPosition.chapterName
//
//        updatedReadingPosition.lastPosition[0] = savedPosition.pageNumber
//        updatedReadingPosition.lastPosition[1] = Int(savedPosition.pageOffset.x.rounded())
//        updatedReadingPosition.lastPosition[2] = Int(savedPosition.pageOffset.y.rounded())
//        updatedReadingPosition.lastReadPage = savedPosition.pageNumber
//        updatedReadingPosition.maxPage = savedPosition.maxPage
//
//        updatedReadingPosition.cfi = savedPosition.cfi
//
//        updatedReadingPosition.readerName = ReaderType.YabrEPUB.rawValue
//        updatedReadingPosition.epoch = savedPosition.epoch.timeIntervalSince1970
        
        let obj = BookDeviceReadingPositionRealm()
        obj.fromFolioReaderReadPosition(savedPosition, bookId: "")

        modelData?.updatedReadingPosition = BookDeviceReadingPosition(managedObject: obj)
    }

    open func initializeWebServer() -> Void {
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        webServer.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { request in
            guard let path = request.path.removingPercentEncoding else { return GCDWebServerErrorResponse() }
            print("\(#function) GCDREQUEST path=\(path)")
            
//            if path.hasSuffix("css") {
//                return GCDWebServerDataResponse(text:
//                """
//                
//                """)
//            }
            
            var pathSegs = path.split(separator: "/")
            guard pathSegs.count > 1 else { return GCDWebServerErrorResponse() }
            pathSegs.removeFirst()
            let resourcePath = pathSegs.joined(separator: "/")
            
            //The Archive class maintains the state of its underlying file descriptor for performance reasons and is therefore not re-entrant. #29
            guard let archiveURL = self.epubArchive?.url,
                  let archive = Archive(url: archiveURL, accessMode: .read),
                  let entry = archive[resourcePath] else { return GCDWebServerErrorResponse() }
            
            var contentType = GCDWebServerGetMimeTypeForExtension((resourcePath as NSString).pathExtension, nil)
            if contentType.contains("text/") {
                contentType += ";charset=utf-8"
            }
            
            var dataQueue = [Data]()
            var isError = false
            
            let streamResponse = GCDWebServerStreamedResponse(
                contentType: contentType,
                asyncStreamBlock: { block in
                    DispatchQueue.global(qos: .userInteractive).async {
                        while( dataQueue.isEmpty && isError == false ) {
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        print("\(#function) async-stream-block \(resourcePath) dataQueueCount=\(dataQueue.count)")
                        
                        DispatchQueue.main.async {
                            if isError {
                                block(nil, UncompressError())
                            } else {
                                block(dataQueue.removeFirst(), nil)
                            }
                        }
                    }
                }
            )
            
            if let modificationDate = entry.fileAttributes[.modificationDate] as? Date {
                streamResponse.setValue(self.dateFormatter.string(from: modificationDate), forAdditionalHeader: "Last-Modified")
                streamResponse.cacheControlMaxAge = 60
            }
            
            var totalCount = 0
            let entrySize = entry.uncompressedSize
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let _ = try archive.extract(entry) { data in
                        while( dataQueue.count > 4) {
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        let d = Data(data)
                        DispatchQueue.main.async {
                            dataQueue.append(d)
                            totalCount += data.count
                            if totalCount >= entrySize {
                                dataQueue.append(Data())
                            }
                        }
                        print("\(#function) zipfile-deflate \(resourcePath) dataCount=\(data.count)")
                    }
                } catch {
                    print("\(#function) zipfile-deflate-error \(resourcePath) error=\(error.localizedDescription)")
                    isError = true
                }
            }
            
            return streamResponse
        }
        
        webServer.addHandler(forMethod: "GET", pathRegex: "^/_fonts/.+?(otf|ttf)$", request: GCDWebServerRequest.self) { request in
            let fileName = (request.path as NSString).lastPathComponent
            print("\(#function) GCDREQUEST FONT fileName=\(fileName) path=\(request.path)")

            guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            else { return nil }
            
            let fontFileURL = documentDirectory.appendingPathComponent("Fonts",  isDirectory: true).appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fontFileURL.path) else { return GCDWebServerErrorResponse() }
            
            guard let fileResponse = GCDWebServerFileResponse(file: fontFileURL.path) else { return GCDWebServerErrorResponse() }
            
            return fileResponse
        }
        
        try? webServer.start(options: [
            GCDWebServerOption_Port: kGCDWebServerPreferredPort,
            GCDWebServerOption_BindToLocalhost: true
        ])
        
        // fallback
        if webServer.isRunning == false {
            try? webServer.start(options: [
                GCDWebServerOption_BindToLocalhost: true,
            ])
            
            if webServer.isRunning == false {
                try? webServer.start(options: [
                    GCDWebServerOption_BindToLocalhost: true
                ])
            }
        }
        
    }
}

struct UncompressError: Error {
    
}
