//
//  SectionShelfController.swift
//  ShelfView_Example
//
//  Created by Adeyinka Adediji on 26/12/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import ShelfView
import SwiftUI
import Combine
import RealmSwift

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class SectionShelfController: UIViewController, SectionShelfCompositionalViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var tabBarHeight = CGFloat(0)
    
    var shelfView: SectionShelfCompositionalView!
    var shelfBookSink: AnyCancellable?

    #if canImport(GoogleMobileAds)
    var bannerSize = GADAdSizeBanner
    var bannerView: GADBannerView!
    var gadRequestInitialized = false
    #else
    var bannerSize = CGRect.zero
    #endif

    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!
    var updateAndReloadCancellable: AnyCancellable?
    var dismissControllerCancellable: AnyCancellable?
    
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    func updateBookModel(reload: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bookModelSection = self.modelData.updateBookModel()
            DispatchQueue.main.async {
                self.modelData.bookModelSection = bookModelSection
                if reload {
                    self.reloadBookModel()
                }
            }
        }
    }

    func reloadBookModel() {
        self.shelfView.reloadBooks(bookModelSection: modelData.bookModelSection)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resizeSubviews(to: view.frame.size, to: traitCollection)
        
        #if canImport(GoogleMobileAds)
        guard gadRequestInitialized == false else { return }
        gadRequestInitialized = true
        let gadRequest = GADRequest()
        gadRequest.scene = self.view.window?.windowScene
        bannerView.load(gadRequest)
        #endif
        
        updateAndReloadCancellable?.cancel()
        updateAndReloadCancellable = modelData.booksRefreshedPublisher
            .collect(Publishers.TimeGroupingStrategy.byTime(RunLoop.main, .seconds(10)))
            .sink { _ in
                self.updateBookModel(reload: true)
            }
        
        dismissControllerCancellable?.cancel()
        dismissControllerCancellable = modelData.readingBookRemovedFromShelfPublisher.sink { _ in
            self.dismiss(animated: true, completion: nil)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let tabBarController = self.tabBarController {
            tabBarHeight = tabBarController.tabBar.frame.height
        }
        updateBookModel()
        
        #if canImport(GoogleMobileAds)
        shelfView = SectionShelfCompositionalView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: view.frame.width,
                height: view.frame.height - kGADAdSizeBanner.size.height
            ),
            bookModelSection: modelData.bookModelSection,
            bookSource: SectionShelfView.BOOK_SOURCE_URL)
        shelfView.translatesAutoresizingMaskIntoConstraints = false
        
        print("SECTIONFRAME \(view.frame) \(kGADAdSizeBanner.size) \(tabBarHeight)")
        
        shelfView.delegate = self
        view.addSubview(shelfView)
        
        bannerView = GADBannerView(
            frame: CGRect(
                x: 0,
                y: shelfView.frame.maxY,
                width:  kGADAdSizeBanner.size.width,
                height: kGADAdSizeBanner.size.height))
        #if DEBUG
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        #else
        bannerView.adUnitID = modelData.resourceFileDictionary?.value(forKey: "GADBannerShelfUnitID") as? String ?? "ca-app-pub-3940256099942544/2934735716"
        #endif
        bannerView.rootViewController = self
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adSize = kGADAdSizeBanner
        
        view.addSubview(bannerView)
        
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: bannerView.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            bannerView.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: kGADAdSizeBanner.size.height / -2)
        ])
        
        #else
        shelfView = SectionShelfView(
            frame: CGRect(
                x: 0,
                y: statusBarHeight,
                width: view.frame.width,
                height: view.frame.height - statusBarHeight
            ),
            bookModelSection: [],
            bookSource: SectionShelfView.BOOK_SOURCE_URL)
        shelfView.delegate = self
        view.addSubview(shelfView)
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        #endif
        
//        NotificationCenter.default.addObserver(modelData.booksInShelf, selector: #selector(updateAndReload), name: nil, object: nil)
        
    }

    func resizeSubviews(to size: CGSize, to newCollection: UITraitCollection) {
        if let tabBarController = self.tabBarController {
            tabBarHeight = tabBarController.tabBar.frame.height
        }
        
        #if canImport(GoogleMobileAds)
        if newCollection.horizontalSizeClass == .regular && newCollection.verticalSizeClass == .regular {
            bannerSize = kGADAdSizeLeaderboard
        }
        if newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .regular {
            bannerSize = kGADAdSizeLargeBanner
        }
        if newCollection.horizontalSizeClass == .regular && newCollection.verticalSizeClass == .compact {
            bannerSize = kGADAdSizeFullBanner
        }
        if newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .compact {
            bannerSize = kGADAdSizeBanner
        }
        
        bannerView.adSize = bannerSize
        
        bannerView.frame = CGRect(
            x: (size.width - bannerSize.size.width) / 2,
            y: size.height - bannerSize.size.height,
            width: bannerSize.size.width,
            height: bannerSize.size.height
        )
        
        #endif
        
        shelfView.frame = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: size.height - bannerSize.size.height
        )
        
        #if canImport(GoogleMobileAds)
        print("SECTIONFRAME \(view.frame) \(shelfView.frame) \(bannerView.frame) \(tabBarHeight) \(bannerSize.size)")
        #endif
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate { _ in
            
        } completion: { _ in
            self.resizeSubviews(to: self.view.frame.size, to: self.traitCollection)
        }

        
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            
        } completion: { _ in
            self.resizeSubviews(to: self.view.frame.size, to: self.traitCollection)
        }
        
    }
    
    func onBookClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String) {
//        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")
//
//        modelData.readingBookInShelfId = bookId
//
//        guard modelData.readingBook != nil else {
//            let alert = UIAlertController(title: "Missing Book File", message: "Re-download from Server?", preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
//                alert.dismiss(animated: true, completion: nil)
//            })
//            alert.addAction(UIAlertAction(title: "Download", style: .default) { _ in
//                alert.dismiss(animated: true, completion: nil)
//            })
//            self.present(alert, animated: true, completion: nil)
//            return
//        }
//        modelData.presentingEBookReaderFromShelf = true
//
//        guard let book = modelData.readingBook, let readerInfo = modelData.readerInfo else { return }
//        modelData.logBookDeviceReadingPositionHistoryStart(book: book, startPosition: readerInfo.position, startDatetime: Date())
        
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")

        modelData.readingBookInShelfId = bookId
//        let detailMenuItem = UIMenuItem(title: "Details", action: #selector(onBookLongClickedDetailMenuItem(_:)))
//        UIMenuController.shared.menuItems = [detailMenuItem]
//        becomeFirstResponder()
//        UIMenuController.shared.showMenu(from: shelfView, rect: inShelfView)
        
        let bookDetailView = BookDetailView(viewMode: .SHELF).environmentObject(modelData)
        let detailView = UIHostingController(
            rootView: bookDetailView
        )
        
        let nav = UINavigationController(rootViewController: detailView)
        nav.modalPresentationStyle = .fullScreen
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.prefersLargeTitles = true
        //nav.setToolbarHidden(false, animated: true)
        
        detailView.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        self.present(nav, animated: true, completion: nil)
    }

    func onBookLongClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")

        modelData.readingBookInShelfId = bookId
//        let detailMenuItem = UIMenuItem(title: "Details", action: #selector(onBookLongClickedDetailMenuItem(_:)))
//        UIMenuController.shared.menuItems = [detailMenuItem]
//        becomeFirstResponder()
//        UIMenuController.shared.showMenu(from: shelfView, rect: inShelfView)
        
        let bookDetailView = BookDetailView(viewMode: .SHELF).environmentObject(modelData)
        let detailView = UIHostingController(
            rootView: bookDetailView
        )
        
        let nav = UINavigationController(rootViewController: detailView)
        nav.modalPresentationStyle = .fullScreen
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.prefersLargeTitles = true
        //nav.setToolbarHidden(false, animated: true)
        
        detailView.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        self.present(nav, animated: true, completion: nil)
    }
    
    func onBookOptionsClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        
    }
    
    func onBookRefreshClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked refresh \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")
        
        guard let book = modelData.booksInShelf[bookId] else { return }
        
        book.formats.filter {
            $1.cached && !$1.cacheUptoDate
        }.keys.forEach {
            guard let format = Format(rawValue: $0) else { return }
            let started = modelData.startDownloadFormat(book: book, format: format, overwrite: true)
            if started {
                
            }
        }
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true) {
            self.modelData.readingBookInShelfId = nil
        }
    }
    
    func delay(_ delay: Double, closure: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
            execute: closure
        )
    }

}
