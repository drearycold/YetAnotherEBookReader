//
//  PlainShelfController.swift
//  ShelfView
//
//  Created by tdscientist on 09/23/2017.
//  Copyright (c) 2017 tdscientist. All rights reserved.
//

import ShelfView
import SwiftUI
import Combine

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class PlainShelfController: UIViewController, PlainShelfViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var tabBarHeight = CGFloat(0)

    var bookModel = [BookModel]()
    var shelfView: PlainShelfView!
    var shelfBookSink: AnyCancellable?
    
#if canImport(GoogleMobileAds)
    var bannerSize = kGADAdSizeBanner
    var bannerView: GADBannerView!
    var gadRequestInitialized = false
#endif

    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!

    override var canBecomeFirstResponder: Bool {
        true
    }
    
    @objc func updateBookModel() {
        bookModel = modelData.booksInShelf
            .filter { $0.value.library.server.isLocal }
            .sorted { $0.value.title < $1.value.title }
            .map { (key: String, value: CalibreBook) -> BookModel in
            BookModel(
                bookCoverSource: value.coverURL.absoluteString,
                bookId: key,
                bookTitle: value.title)
        }
        
        self.shelfView.reloadBooks(bookModel: bookModel)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resizeSubviews(to: view.frame.size, to: traitCollection)
        
        //updateBookModel()
        guard gadRequestInitialized == false else { return }
        gadRequestInitialized = true
        let gadRequest = GADRequest()
        gadRequest.scene = self.view.window?.windowScene
        bannerView.load(gadRequest)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        shelfView = PlainShelfView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: view.frame.width,
                height: view.frame.height - kGADAdSizeBanner.size.height
            ),
            bookModel: bookModel,
            bookSource: PlainShelfView.BOOK_SOURCE_URL)
        
        shelfView.delegate = self
        shelfView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(shelfView)
        
        #if canImport(GoogleMobileAds)
        bannerView = GADBannerView(
            frame: CGRect(
                x: 0,
                y: shelfView.frame.maxY,
                width:  kGADAdSizeBanner.size.width,
                height: kGADAdSizeBanner.size.height)
        )
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
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
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
//            bannerView.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: kGADAdSizeBanner.size.height / -2)
        ])
        #else
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        #endif
        
        shelfBookSink = modelData.$booksInShelf.sink { [weak self] _ in
            self?.updateBookModel()
        }
    }

    func resizeSubviews(to size: CGSize, to newCollection: UITraitCollection) {
        if let tabBarController = self.tabBarController {
            tabBarHeight = tabBarController.tabBar.frame.height
        }
        
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
        
        shelfView.frame = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: size.height - bannerSize.size.height
        )
        bannerView.frame = CGRect(
            x: (size.width - bannerSize.size.width) / 2,
            y: size.height - bannerSize.size.height,
            width: bannerSize.size.width,
            height: bannerSize.size.height
        )
        
        print("SECTIONFRAME \(view.frame) \(shelfView.frame) \(bannerView.frame) \(tabBarHeight) \(bannerSize.size)")
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
    
    func onBookClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        
        modelData.presentingEBookReaderFromShelf = true

    }
    
    func onBookLongClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        let refreshMenuItem = UIMenuItem(title: "Refresh", action: #selector(refreshBook(_:)))
        let deleteMenuItem = UIMenuItem(title: "Delete", action: #selector(deleteBook(_:)))
        UIMenuController.shared.menuItems = [refreshMenuItem, deleteMenuItem]
        becomeFirstResponder()
        UIMenuController.shared.showMenu(from: shelfView, rect: inShelfView)
    }

    @objc func refreshBook(_ sender: Any?) {
        print("refreshBook")
        
        updateBookModel()
    }
    
    @objc func deleteBook(_ sender: Any?) {
        print("deleteBook")
        guard let inShelfId = modelData.readingBookInShelfId,
              let book = modelData.booksInShelf[inShelfId] else { return }
        
        book.formats.keys.forEach {
            guard let format = CalibreBook.Format(rawValue: $0) else { return }
            modelData.clearCache(book: book, format: format)
            modelData.deleteLocalLibraryBook(book: book, format: format)
        }

        modelData.removeFromShelf(inShelfId: inShelfId)
        
        updateBookModel()
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
        modelData.readingBookInShelfId = nil
    }
    
    func delay(_ delay: Double, closure: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
            execute: closure
        )
    }

}
