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

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

internal let kGCDWebServerPreferredPort = 46436

@available(macCatalyst 14.0, *)
class EpubFolioReaderContainer: FolioReaderContainer {
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

#if canImport(GoogleMobileAds)
    let bannerSize = GADAdSizeMediumRectangle
    var interstitialAd: GADInterstitialAd?
#endif
    
    func open(bookReadingPosition: BookDeviceReadingPosition) {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        self.yabrFolioReaderPageDelegate = YabrFolioReaderPageDelegate(readerConfig: self.readerConfig)
        self.folioReader.delegate = self
        
        let position = bookReadingPosition.toFolioReaderReadPosition()
        
        readerConfig.savedPositionForCurrentBook = position
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willResignActiveNotification, object: nil)
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willTerminateNotification, object: nil)
        
#if GAD_ENABLED
        let gadRequest = GADRequest()
        //        gadRequest.scene = self.view.window?.windowScene
        gadRequest.scene = UIApplication.shared.keyWindow?.rootViewController?.view.window?.windowScene
        
        GADInterstitialAd.load(withAdUnitID: "ca-app-pub-3940256099942544/4411468910", request: gadRequest) { ad, error in
            if let error = error {
                print("\(#function) interstitial error=\(error.localizedDescription)")
                return
            }
            self.interstitialAd = ad
            self.interstitialAd?.fullScreenContentDelegate = self
        }
#endif
        
        super.initialization()
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

extension EpubFolioReaderContainer: FolioReaderDelegate {
    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        folioReader.readerCenter?.delegate = MyFolioReaderCenterDelegate()
        folioReader.readerCenter?.pageDelegate = yabrFolioReaderPageDelegate
        
        self.epubArchive = book.epubArchive
        initializeWebServer()
        readerConfig.serverPort = Int(webServer.port)
        
//        if let bookId = readerConfig.identifier,
//           let savedPosition = readerConfig.savedPositionForCurrentBook,
//           let provider = folioReader.delegate?.folioReaderReadPositionProvider?(folioReader) {
//            provider.folioReaderPositionHistory?(folioReader, bookId: bookId, start: savedPosition)
//        }
        
#if canImport(GoogleMobileAds)

#endif
        
    }
    
    func folioReaderDidClose(_ folioReader: FolioReader) {
        webServer.stop()
        
//        if let bookId = readerConfig.identifier,
//           let savedPosition = folioReader.savedPositionForCurrentBook,
//           let provider = folioReader.delegate?.folioReaderReadPositionProvider?(folioReader) {
//            provider.folioReaderPositionHistory?(folioReader, bookId: bookId, finish: savedPosition)
//        }
    }
    
    func folioReaderAdView(_ folioReader: FolioReader) -> UIView? {
#if canImport(GoogleMobileAds)
        let bannerView = GADBannerView(
            frame: .init(origin: .zero, size: bannerSize.size)
        )
#if DEBUG
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ "23e0202ad7a1682137a4ad8bccc0e35b" ]
#else
        bannerView.adUnitID = modelData?.resourceFileDictionary?.value(forKey: "GADBannerShelfUnitID") as? String ?? "ca-app-pub-3940256099942544/2934735716"
#endif
        bannerView.rootViewController = self
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adSize = bannerSize
        
#if GAD_ENABLED
        let gadRequest = GADRequest()
        //        gadRequest.scene = self.view.window?.windowScene
        gadRequest.scene = UIApplication.shared.keyWindow?.rootViewController?.view.window?.windowScene
        bannerView.load(gadRequest)
#endif
        return bannerView
#else
        return nil
#endif
        
    }
    
    func folioReaderAdPresent(_ folioReader: FolioReader) {
#if canImport(GoogleMobileAds)
        guard let interstitialAd = interstitialAd else {
            initInterstitialAd()
            return
        }
        guard let readerCenter = folioReader.readerCenter else { return }
        
        interstitialAd.present(fromRootViewController: readerCenter)
#endif
    }
}

#if canImport(GoogleMobileAds)
extension EpubFolioReaderContainer: GADFullScreenContentDelegate {
    func initInterstitialAd() {
        self.interstitialAd = nil
        
        let gadRequest = GADRequest()
        //        gadRequest.scene = self.view.window?.windowScene
        gadRequest.scene = UIApplication.shared.keyWindow?.rootViewController?.view.window?.windowScene
        
        GADInterstitialAd.load(withAdUnitID: "ca-app-pub-3940256099942544/4411468910", request: gadRequest) { ad, error in
            if let error = error {
                print("\(#function) interstitial error=\(error.localizedDescription)")
                return
            }
            self.interstitialAd = ad
            self.interstitialAd?.fullScreenContentDelegate = self
        }
    }
    
    func adWillDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {

    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        initInterstitialAd()
    }
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("\(#function) interstitial present error=\(error.localizedDescription)")
    }
}
#endif

struct UncompressError: Error {
    
}
