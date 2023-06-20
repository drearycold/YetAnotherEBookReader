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
    var tabBarHeight = CGFloat(0)

    var shelfView: PlainShelfView!
    
    #if canImport(GoogleMobileAds)
    var bannerSize = GADAdSizeBanner
    var bannerView: GADBannerView!
    var gadRequestInitialized = false
    #else
    var bannerSize = CGRect.zero
    #endif

    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!
    var dismissControllerCancellable: AnyCancellable?
    var reloadShelfCancellable: AnyCancellable?
    
    var bookDetailViewPresentingId: String? = nil

    var menuTargetRect: CGRect!     //used by secondary menu, make sure it's properly set
    
    let refreshBarButtonItem = BarButtonItem()

    override var canBecomeFirstResponder: Bool {
        true
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
        bannerView.adUnitID = modelData.yabrGADBannerShelfUnitID

        #if DEBUG
        if let deviceId = modelData.yabrGADDeviceIdentifierTest {
            GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ deviceId ]
        }
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
        ])
        #else
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        #endif
        
        reloadShelfCancellable?.cancel()
        reloadShelfCancellable = modelData.recentShelfModelSubject
            .receive(on: DispatchQueue.main)
            .sink { bookModel in
                self.shelfView.reloadBooks(bookModel: bookModel)
            }
        
        let navBarBackgroundImage = Utils().loadImage(name: "header")?.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5))
        
        let navBarScrollApp = UINavigationBarAppearance()
        navBarScrollApp.configureWithTransparentBackground()
        navBarScrollApp.backgroundImage = navBarBackgroundImage
        self.navigationController?.navigationBar.standardAppearance = navBarScrollApp
        self.navigationController?.navigationBar.scrollEdgeAppearance = navBarScrollApp
        
        refreshBarButtonItem.primaryAction = .init(title: "Refresh", handler: { action in
            self.modelData.refreshShelfMetadataV2(serverReachableChanged: false)
            
            self.modelData.probeServersReachability(with: [], updateLibrary: true)
        })
        
        self.navigationItem.setLeftBarButtonItems([
            refreshBarButtonItem
        ], animated: false)
        
        self.navigationItem.setRightBarButtonItems([
            self.editButtonItem
        ], animated: false)
        
        let toolBarApp = UIToolbarAppearance()
        toolBarApp.configureWithOpaqueBackground()
        toolBarApp.backgroundImage = navBarBackgroundImage
        self.navigationController?.toolbar.standardAppearance = toolBarApp
        self.navigationController?.toolbar.scrollEdgeAppearance = toolBarApp
        
        self.setToolbarItems([
            .init(title: "Select All", style: .plain, target: shelfView, action: #selector(shelfView.selectAll(_:))),
            UIBarButtonItem.flexibleSpace(),
            .init(title: "Delete", style: .done, target: self, action: #selector(deleteBooks(_:))),
            UIBarButtonItem.flexibleSpace(),
            .init(title: "Clear", style: .plain, target: shelfView, action: #selector(shelfView.clearSelection(_:)))
        ], animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resizeSubviews(to: view.frame.size, to: traitCollection)
        
        //updateBookModel()
        #if canImport(GoogleMobileAds)
        #if GAD_ENABLED
        guard gadRequestInitialized == false else { return }
        gadRequestInitialized = true
        let gadRequest = GADRequest()
//        gadRequest.scene = self.view.window?.windowScene
        gadRequest.scene = UIApplication.shared.keyWindow?.rootViewController?.view.window?.windowScene
        bannerView.load(gadRequest)
        #endif
        #endif
        
        dismissControllerCancellable?.cancel()
        dismissControllerCancellable = modelData.calibreUpdatedSubject.sink { signal in
            guard let bookId = self.bookDetailViewPresentingId, signal == .deleted(bookId) else { return }
            self.dismiss(animated: true, completion: { self.bookDetailViewPresentingId = nil })
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
            height: size.height - bannerSize.size.height - (isEditing ? 50 : 0)
        )
        
        if var toolbarFrame = self.navigationController?.toolbar.frame {
            self.navigationController?.toolbar.frame = toolbarFrame.offsetBy(dx: 0, dy: -50)
        }
        
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
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        shelfView.setEditing(editing)
        
        self.navigationController?.setToolbarHidden(!editing, animated: false)
        
        if self.navigationController?.isToolbarHidden == false,
           let toolbar = self.navigationController?.toolbar {
            NSLayoutConstraint.activate([
                toolbar.bottomAnchor.constraint(equalTo: shelfView.bottomAnchor)
            ])
        }
        
//        if editing == false {
            self.resizeSubviews(to: self.view.frame.size, to: self.traitCollection)
//        }
    }
    
    func onBookClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        guard let book = modelData.readingBook else { return }
        
        let readerInfo = modelData.prepareBookReading(book: book)
        
        if readerInfo.missing {
            if let activeDownload = modelData.activeDownloads.first(where: {
                $0.value.book == book && $0.value.format == readerInfo.format
            }),
               activeDownload.value.isDownloading {
                let alert = UIAlertController(title: "Downloading Format", message: "Please wait a few moment", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: { _ in
                    alert.dismiss(animated: true)
                }))
                alert.addAction(UIAlertAction(title: "Restart", style: .default, handler: { _ in
                    self.modelData.bookFormatDownloadSubject.send((book: book, format: readerInfo.format))
                    alert.dismiss(animated: true)
                }))
                self.present(alert, animated: true)
            } else {
                let alert = UIAlertController(title: "Missing Format", message: "Try Download Now?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                    alert.dismiss(animated: true)
                }))
                alert.addAction(UIAlertAction(title: "Download", style: .default, handler: { _ in
                    self.modelData.bookFormatDownloadSubject.send((book: book, format: readerInfo.format))
                    alert.dismiss(animated: true)
                }))
                self.present(alert, animated: true)
            }
        } else {
            modelData.readerInfo = readerInfo
            
            modelData.presentingEBookReaderFromShelf = true
        }
    }
    
    func onBookLongClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        guard let book = modelData.readingBook else { return }
        
        if book.library.server.isLocal {
            //same as options
            onBookOptionsClicked(shelfView, index: index, bookId: bookId, bookTitle: bookTitle, frame: inShelfView)
        } else if let bookRealm = modelData.getBookRealm(forPrimaryKey: bookId),
                  let bookAnnoRealm = book.readPos.realm {
            
            let bookDetailView = BookDetailView(book: bookRealm, viewMode: .SHELF)
                .environmentObject(modelData)
                .environment(\.realmConfiguration, bookAnnoRealm.configuration)
            
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
                self.bookDetailViewPresentingId = bookId
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

            self.modelData.bookFormatDownloadSubject.send((book: book, format: format))
        }
    }
    
    func onBookProgressClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked progress \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        
        guard let bookRealm = modelData.getBookRealm(forPrimaryKey: bookId),
              let book = modelData.readingBook,
              let bookAnnoRealm = book.readPos.realm
        else {
            return
        }
        
        let readingPositionHistoryView = UIHostingController(
            rootView: ReadingPositionHistoryView(
                presenting: Binding<Bool>(get: { true }, set: { _ in }),
                library: book.library,
                bookId: book.id
            ).environmentObject(modelData)
                .environment(\.realmConfiguration, bookAnnoRealm.configuration)
        )
        
        let nav = UINavigationController(rootViewController: readingPositionHistoryView)
        nav.modalPresentationStyle = .automatic
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.prefersLargeTitles = true
        //nav.setToolbarHidden(false, animated: true)
        
        readingPositionHistoryView.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        self.present(nav, animated: true, completion: {
            self.bookDetailViewPresentingId = bookId
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
        
    }
    
    @objc func deleteBook(_ sender: Any?) {
        print("deleteBook")
        guard let book = modelData.readingBook,
              book.inShelfId == modelData.readingBookInShelfId  else { return }
        
        modelData.clearCache(inShelfId: book.inShelfId)
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
        modelData.readingBookInShelfId = nil
        self.bookDetailViewPresentingId = nil
    }

    @objc func deleteBooks(_ sender: Any?) {
        let count = self.shelfView.selectedBookIds.count
        guard count > 0 else { return }
        
        let alert = UIAlertController(title: "Delete Books?", message: "Will delete \(count) books from reading shelf, are you sure?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.shelfView.selectedBookIds.forEach {
                self.modelData.clearCache(inShelfId: $0)
            }
            self.setEditing(false, animated: true)
            
            self.modelData.calibreUpdatedSubject.send(.shelf)
        })
        
        self.present(alert, animated: true)
    }
}
