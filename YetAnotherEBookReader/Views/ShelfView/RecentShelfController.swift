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

class RecentShelfController: UIViewController, PlainShelfViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var tabBarHeight = CGFloat(0)

    var bookModel = [BookModel]()
    var shelfView: PlainShelfView!
//    var shelfBookSink: AnyCancellable?
    
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
    var bookDetailViewPresenting = false

    var menuTargetRect: CGRect!     //used by secondary menu, make sure it's properly set
    
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    @objc func updateBookModel() {
        bookModel = modelData.booksInShelf
//            .filter { $0.value.lastModified > Date(timeIntervalSinceNow: -86400 * 30) || $0.value.library.server.isLocal }
            .sorted { max($0.value.lastModified, $0.value.lastUpdated) > max($1.value.lastModified, $1.value.lastUpdated) }
            .compactMap { (inShelfId, book) in
                guard let coverUrl = book.coverURL else { return nil }
                guard let readerInfo = modelData.prepareBookReading(book: book) else { return nil }
                
                let bookUptoDate = book.formats.allSatisfy {
                    $1.cached == false ||
                        ($1.cached && $1.cacheUptoDate)
                }
                var bookStatus = BookModel.BookStatus.READY
                if modelData.calibreServerService.getServerUrlByReachability(server: book.library.server) == nil {
                    bookStatus = .NOCONNECT
                } else {
                    if !bookUptoDate {
                        bookStatus = .HASUPDATE
                    }
                    if modelData.activeDownloads.contains(where: { (url, download) in
                        download.isDownloading && download.book.inShelfId == inShelfId
                    }) {
                        bookStatus = .DOWNLOADING
                    }
                }
                if book.library.server.isLocal {
                    bookStatus = .LOCAL
                }
                
                return BookModel(
                    bookCoverSource: coverUrl.absoluteString,
                    bookId: inShelfId,
                    bookTitle: book.title,
                    bookProgress: Int(floor(readerInfo.position.lastProgress)),
                    bookStatus: bookStatus
                )
            }
        print("\(#function) modelData.booksInShelf.count=\(modelData.booksInShelf.count) bookModel.count=\(bookModel.count)")

        self.shelfView.reloadBooks(bookModel: bookModel)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resizeSubviews(to: view.frame.size, to: traitCollection)
        
        //updateBookModel()
        #if canImport(GoogleMobileAds)
        guard gadRequestInitialized == false else { return }
        gadRequestInitialized = true
        let gadRequest = GADRequest()
        gadRequest.scene = self.view.window?.windowScene
        bannerView.load(gadRequest)
        #endif
        
        
        dismissControllerCancellable?.cancel()
        dismissControllerCancellable = modelData.readingBookRemovedFromShelfPublisher.sink { _ in
            guard self.bookDetailViewPresenting else { return }
            self.dismiss(animated: true, completion: { self.bookDetailViewPresenting = false })
        }
        
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        shelfView = PlainShelfView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: view.frame.width,
                height: view.frame.height - bannerSize.size.height
            )
        )
        
        shelfView.delegate = self
        shelfView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(shelfView)
        
        #if canImport(GoogleMobileAds)
        bannerView = GADBannerView(
            frame: CGRect(
                x: 0,
                y: shelfView.frame.maxY,
                width:  GADAdSizeBanner.size.width,
                height: GADAdSizeBanner.size.height)
        )
        #if DEBUG
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ "23e0202ad7a1682137a4ad8bccc0e35b" ]
        #else
        bannerView.adUnitID = modelData.resourceFileDictionary?.value(forKey: "GADBannerShelfUnitID") as? String ?? "ca-app-pub-3940256099942544/2934735716"
        #endif
        bannerView.rootViewController = self
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adSize = GADAdSizeBanner

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
        
        self.updateBookModel()
//        shelfBookSink = modelData.$booksInShelf.sink { [weak self] _ in
//            self?.updateBookModel()
//        }
        
        updateAndReloadCancellable = modelData.booksRefreshedPublisher
            .subscribe(on: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                self.updateBookModel()
            }
        
    }

    func resizeSubviews(to size: CGSize, to newCollection: UITraitCollection) {
        if let tabBarController = self.tabBarController {
            tabBarHeight = tabBarController.tabBar.frame.height
        }
        
        #if canImport(GoogleMobileAds)
        if newCollection.horizontalSizeClass == .regular && newCollection.verticalSizeClass == .regular {
            bannerSize = GADAdSizeLeaderboard
        }
        if newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .regular {
            bannerSize = GADAdSizeLargeBanner
        }
        if newCollection.horizontalSizeClass == .regular && newCollection.verticalSizeClass == .compact {
            bannerSize = GADAdSizeFullBanner
        }
        if newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .compact {
            bannerSize = GADAdSizeBanner
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
    
    func onBookClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        guard modelData.readingBook != nil, modelData.readerInfo != nil else { return }

        modelData.presentingEBookReaderFromShelf = true
    }
    
    func onBookLongClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        guard let book = modelData.readingBook else { return }
        
        if book.library.server.isLocal {
            //same as options
            onBookOptionsClicked(shelfView, index: index, bookId: bookId, bookTitle: bookTitle, frame: inShelfView)
        } else {
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
            
            self.present(nav, animated: true, completion: {
                self.bookDetailViewPresenting = true
            })
        }
    }
    
    func onBookOptionsClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked options \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        guard let book = modelData.readingBook else { return }
        
        let detailMenuItem = UIMenuItem(title: "Details", action: #selector(detailAction))
        let refreshMenuItem = UIMenuItem(title: "Refresh", action: #selector(refreshBook(_:)))
        let deleteMenuItem = UIMenuItem(title: book.library.server.isLocal ? "Delete" : "Remove", action: #selector(deleteBook(_:)))
        let gotoMenuItem = UIMenuItem(title: "Go to ...", action: #selector(gotoAction))
        
        menuTargetRect = inShelfView
        UIMenuController.shared.menuItems = [detailMenuItem, refreshMenuItem, deleteMenuItem, gotoMenuItem]
        becomeFirstResponder()
        UIMenuController.shared.showMenu(from: shelfView, rect: inShelfView)
    }

    func onBookRefreshClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked refresh \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        guard let book = modelData.booksInShelf[bookId] else { return }
        
        book.formats.filter {
            $1.cached && !$1.cacheUptoDate
        }.keys.forEach {
            guard let format = Format(rawValue: $0) else { return }
            let started = modelData.startDownloadFormat(book: book, format: format, overwrite: true)
            if started {
                NotificationCenter.default.post(Notification(name: .YABR_BooksRefreshed))
            }
        }
    }
    
    func onBookProgressClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked progress \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        guard let book = modelData.readingBook else { return }
        
        
        let readingPositionHistoryView = UIHostingController(
            rootView: ReadingPositionHistoryView(libraryId: book.library.id, bookId: book.id).environmentObject(modelData)
        )
        
        let nav = UINavigationController(rootViewController: readingPositionHistoryView)
        nav.modalPresentationStyle = .automatic
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.prefersLargeTitles = true
        //nav.setToolbarHidden(false, animated: true)
        
        readingPositionHistoryView.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        self.present(nav, animated: true, completion: {
            
        })
    }

    @objc func gotoAction(_ sender: Any?) {
        let goodreadsMenuItem = UIMenuItem(title: "Goodreads", action: #selector(goodreadsAction))
        let doubanMenuItem = UIMenuItem(title: "Douban", action: #selector(doubanAction))
        
        UIMenuController.shared.hideMenu()
        UIMenuController.shared.menuItems = [goodreadsMenuItem, doubanMenuItem]
        UIMenuController.shared.showMenu(from: shelfView, rect: menuTargetRect)
    }
    
    @objc func goodreadsAction(_ sender: Any?) {
        guard let book = modelData.readingBook else { return }
        
        if let id = book.identifiers["goodreads"],
           let url = URL(string: "https://www.goodreads.com/book/show/\(id)") {
            UIApplication.shared.open(url)
        } else if var urlComponents = URLComponents(string: "https://www.goodreads.com/search") {
            urlComponents.queryItems = [URLQueryItem(name: "q", value: book.title + " " + book.authors.joined(separator: " "))]
            if let url = urlComponents.url {
                UIApplication.shared.open(url)
            }
        }
    }
    
    @objc func doubanAction(_ sender: Any?) {
        guard let book = modelData.readingBook else { return }
        
        if let id = book.identifiers["douban"],
           let url = URL(string: "https://m.douban.com/book/subject/\(id)/") {
            UIApplication.shared.open(url)
        } else if var urlComponents = URLComponents(string: "https://m.douban.com/search/") {
            urlComponents.queryItems = [
                URLQueryItem(name: "query", value: book.title + " " + book.authors.joined(separator: " ")),
                URLQueryItem(name: "type", value: "book")
            ]
            if let url = urlComponents.url {
                UIApplication.shared.open(url)
            }
        }
    }
    
    @objc func detailAction(_ sender: Any?) {
        defer {
            UIMenuController.shared.hideMenu()
        }
        guard let bookId = modelData.readingBookInShelfId else { return }
        self.onBookLongClicked(shelfView, index: 0, bookId: bookId, bookTitle: "", frame: .zero)
    }
    
    @objc func refreshBook(_ sender: Any?) {
        print("refreshBook")
        
        updateBookModel()
    }
    
    @objc func deleteBook(_ sender: Any?) {
        print("deleteBook")
        guard let book = modelData.readingBook,
              book.inShelfId == modelData.readingBookInShelfId  else { return }
        
        modelData.clearCache(inShelfId: book.inShelfId)
        
        updateBookModel()
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
        modelData.readingBookInShelfId = nil
    }

}
