//
//  ViewController.swift
//  Example
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioReaderKit
import ReadiumZIPFoundation

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@available(macCatalyst 14.0, *)
class EpubFolioReaderContainer: FolioReaderContainer {
//    var savedPositionObserver: NSKeyValueObservation?
    var modelData: ModelData?
    
    var yabrFolioReaderPageDelegate: YabrFolioReaderPageDelegate!
    
    var folioReaderPreferenceProvider: FolioReaderPreferenceProvider?
    var folioReaderHighlightProvider: FolioReaderHighlightProvider?
    var folioReaderReadPositionProvider: FolioReaderReadPositionProvider?
    var folioReaderBookmarkProvider: FolioReaderBookmarkProvider?

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
#if canImport(GoogleMobileAds)
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
#endif
        super.initialization()
    }

    
}

extension EpubFolioReaderContainer: FolioReaderDelegate {
    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        folioReader.readerCenter?.delegate = MyFolioReaderCenterDelegate()
        folioReader.readerCenter?.pageDelegate = yabrFolioReaderPageDelegate
        
//        self.epubArchive = book.epubArchive
//        readerConfig.serverPort = Int(webServer.port)
        
//        if let bookId = readerConfig.identifier,
//           let savedPosition = readerConfig.savedPositionForCurrentBook,
//           let provider = folioReader.delegate?.folioReaderReadPositionProvider?(folioReader) {
//            provider.folioReaderPositionHistory?(folioReader, bookId: bookId, start: savedPosition)
//        }
        
#if canImport(GoogleMobileAds)

#endif
        
    }
    
    func folioReaderDidClose(_ folioReader: FolioReader) {
//        DispatchQueue.global(qos: .background).async {
//            self.webServer.stop()
//        }
        
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
        bannerView.adUnitID = modelData?.yabrGADBannerShelfUnitID
#if DEBUG
        if let deviceIdentifier = modelData?.yabrGADDeviceIdentifierTest {
            GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ deviceIdentifier ]
        }
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
