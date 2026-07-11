//
//  ViewController.swift
//  Example
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioReaderKit
import FolioEPUBCore
import ReadiumZIPFoundation

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@available(macCatalyst 14.0, *)
class EpubFolioReaderContainer: FolioReaderContainer {
//    var savedPositionObserver: NSKeyValueObservation?
    var container: AppContainer?
    var calibreBook: CalibreBook?
    var readerInfo: ReaderInfo?
    weak var readerEngineDelegate: ReaderEngineDelegate?
    
    var yabrFolioReaderPageDelegate: YabrFolioReaderPageDelegate!
    
    var folioReaderPreferenceProvider: FolioReaderPreferenceProvider?
    var folioReaderHighlightProvider: FolioReaderHighlightProvider?
    var folioReaderReadPositionProvider: FolioReaderReadPositionProvider?
    var folioReaderBookmarkProvider: FolioReaderBookmarkProvider?
    var uiTestingCloseHandler: (() -> Void)?

    private var yabrFolioReaderCenterDelegate: MyFolioReaderCenterDelegate?
    private var uiTestingPositionLabel: UILabel?
    private var uiTestingCloseButton: UIButton?

    let dateFormatter = DateFormatter()
    var epubArchive: Archive?

    private enum AccessibilityID {
        static let screen = "reader.folio.screen"
        static let content = "reader.folio.content"
        static let position = "reader.folio.position"
        static let close = "reader.folio.close"
    }

#if canImport(GoogleMobileAds)
    let bannerSize = AdSizeMediumRectangle
    var interstitialAd: InterstitialAd?
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
        let gadRequest = Request()
        //        gadRequest.scene = self.view.window?.windowScene
        gadRequest.scene = UIApplication.shared.keyWindow?.rootViewController?.view.window?.windowScene
        
        InterstitialAd.load(with: "ca-app-pub-3940256099942544/4411468910", request: gadRequest) { ad, error in
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = AccessibilityID.screen

        guard UITestingConfiguration.isEnabled() else { return }
        let positionLabel = UILabel(frame: CGRect(x: 8, y: 8, width: 120, height: 20))
        positionLabel.accessibilityIdentifier = AccessibilityID.position
        positionLabel.isAccessibilityElement = true
        positionLabel.text = "Page 1"
        positionLabel.textColor = .clear
        view.addSubview(positionLabel)
        uiTestingPositionLabel = positionLabel

        let closeButton = UIButton(type: .system)
        closeButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        closeButton.accessibilityIdentifier = AccessibilityID.close
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(uiTestingCloseReader), for: .primaryActionTriggered)
        view.addSubview(closeButton)
        uiTestingCloseButton = closeButton
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installCloseAccessibilityIdentifier()
    }

    @objc private func uiTestingCloseReader() {
        uiTestingCloseHandler?()
    }

    
}

extension EpubFolioReaderContainer: FolioReaderDelegate {
    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        let centerDelegate = MyFolioReaderCenterDelegate()
        centerDelegate.pageDidAppearHandler = { [weak self] page in
            self?.uiTestingPositionLabel?.text = "Page \(page.pageNumber)"
            self?.installAccessibilityIdentifiers(for: page)
        }
        centerDelegate.pageItemChangedHandler = { [weak self] pageNumber in
            guard let self else { return }
            let chapterPage = self.folioReader.readerCenter?.currentPage?.pageNumber ?? 0
            self.uiTestingPositionLabel?.text = "Page \(chapterPage)-\(pageNumber)"
        }
        yabrFolioReaderCenterDelegate = centerDelegate
        folioReader.readerCenter?.delegate = centerDelegate
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

        installCloseAccessibilityIdentifier()
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

    private func installAccessibilityIdentifiers(for page: FolioReaderPage) {
        if let collectionView = folioReader.readerCenter?.collectionView {
            collectionView.accessibilityIdentifier = AccessibilityID.screen
        }
        page.webView?.accessibilityIdentifier = AccessibilityID.content
        installCloseAccessibilityIdentifier()
    }

    private func installCloseAccessibilityIdentifier() {
        guard UITestingConfiguration.folioReaderCloseButtonEnabled(),
              let centerViewController = folioReader.readerCenter,
              let closeItem = centerViewController.navigationItem.leftBarButtonItems?.first
        else { return }

        if closeItem.accessibilityIdentifier == AccessibilityID.close {
            return
        }

        closeItem.accessibilityIdentifier = AccessibilityID.close
        guard let uiTestingCloseHandler else { return }

        let replacement = UIBarButtonItem(
            image: closeItem.image,
            primaryAction: UIAction { [weak self] _ in
                self?.folioReader.saveReaderState {
                    uiTestingCloseHandler()
                }
            }
        )
        replacement.accessibilityIdentifier = AccessibilityID.close
        var items = centerViewController.navigationItem.leftBarButtonItems ?? []
        items[0] = replacement
        centerViewController.navigationItem.leftBarButtonItems = items
    }

    func folioReaderAdView(_ folioReader: FolioReader) -> UIView? {
#if canImport(GoogleMobileAds)
        let bannerView = BannerView(
            frame: .init(origin: .zero, size: bannerSize.size)
        )
        bannerView.adUnitID = YabrAppInfo.shared.gadBannerShelfUnitID
#if DEBUG
        if let deviceIdentifier = YabrAppInfo.shared.gadDeviceIdentifierTest {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [ deviceIdentifier ]
        }
#endif
        bannerView.rootViewController = self
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adSize = bannerSize
        
#if GAD_ENABLED
        let gadRequest = Request()
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
        
        interstitialAd.present(from: readerCenter)
#endif
    }
}

#if canImport(GoogleMobileAds)
extension EpubFolioReaderContainer: FullScreenContentDelegate {
    func initInterstitialAd() {
        self.interstitialAd = nil
        
        let gadRequest = Request()
        //        gadRequest.scene = self.view.window?.windowScene
        gadRequest.scene = UIApplication.shared.keyWindow?.rootViewController?.view.window?.windowScene
        
        InterstitialAd.load(with: "ca-app-pub-3940256099942544/4411468910", request: gadRequest) { ad, error in
            if let error = error {
                print("\(#function) interstitial error=\(error.localizedDescription)")
                return
            }
            self.interstitialAd = ad
            self.interstitialAd?.fullScreenContentDelegate = self
        }
    }
    
    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {

    }
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        initInterstitialAd()
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("\(#function) interstitial present error=\(error.localizedDescription)")
    }
}
#endif

struct UncompressError: Error {
    
}
