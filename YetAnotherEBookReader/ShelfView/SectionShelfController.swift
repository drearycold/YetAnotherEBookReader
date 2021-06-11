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

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class SectionShelfController: UIViewController, SectionShelfViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var tabBarHeight = CGFloat(0)
    
    var bookModel = [String: [BookModel]]()
    var bookModelSectionsArray = [BookModelSection]()
    var shelfView: SectionShelfView!
    var shelfBookSink: AnyCancellable?

#if canImport(GoogleMobileAds)
    var bannerSize = kGADAdSizeBanner
    var bannerView: GADBannerView!
#endif

    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    func updateBookModel() {
        bookModel = modelData.booksInShelf
            .filter { $0.value.library.server.isLocal == false }
            .sorted {
                if $0.value.lastModified == $1.value.lastModified {
                    return $0.value.title < $1.value.title
                } else {
                    return $0.value.lastModified > $1.value.lastModified
                }
            }
            .reduce(into: [String: [BookModel]]()) {
                print("updateBookModel \($1.value.title) \($1.value.lastModified)")
                let newBook = BookModel(
                    bookCoverSource: $1.value.coverURL.absoluteString,
                    bookId: $1.key,
                    bookTitle: $1.value.title)
                let shelfName = $1.value.inShelfName.isEmpty ? ($1.value.tags.first ?? "Untagged") : $1.value.inShelfName
                if $0[shelfName] != nil {
                    $0[shelfName]!.append(newBook)
                } else {
                    $0[shelfName] = [newBook]
                }
            }
        bookModelSectionsArray = bookModel.sorted { $0.key < $1.key }.map {
            BookModelSection(sectionName: $0.key, sectionId: $0.key, sectionBooks: $0.value)
        }
        if bookModelSectionsArray.isEmpty {
            bookModelSectionsArray.append(BookModelSection(sectionName: "Default", sectionId: "Default", sectionBooks: []))
        }
    }
        
    func reloadBookModel() {
        self.shelfView.reloadBooks(bookModelSection: bookModelSectionsArray)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resizeSubviews(to: view.frame.size, to: traitCollection)
        
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: bannerView.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            bannerView.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: kGADAdSizeBanner.size.height / -2)
        ])
        
        bannerView.load(GADRequest())
        
        //self.updateBookModel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let tabBarController = self.tabBarController {
            tabBarHeight = tabBarController.tabBar.frame.height
        }
        updateBookModel()
        
        #if canImport(GoogleMobileAds)
        shelfView = SectionShelfView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: view.frame.width,
                height: view.frame.height - kGADAdSizeBanner.size.height
            ),
            bookModelSection: bookModelSectionsArray,
            bookSource: SectionShelfView.BOOK_SOURCE_URL)
        shelfView.translatesAutoresizingMaskIntoConstraints = false
        
        print("SECTIONFRAME \(view.frame) \(kGADAdSizeBanner.size) \(tabBarHeight)")
        
        shelfView.delegate = self
//        shelfBookSink = modelData.$booksInShelf.sink { [weak self] _ in
//            DispatchQueue.main.async {
//                self?.updateBookModel()
//            }
//        }
        view.addSubview(shelfView)
        
        bannerView = GADBannerView(
            frame: CGRect(
                x: 0,
                y: shelfView.frame.maxY,
                width:  kGADAdSizeBanner.size.width,
                height: kGADAdSizeBanner.size.height))
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        bannerView.rootViewController = self
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adSize = kGADAdSizeBanner
        view.addSubview(bannerView)
        
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
    
    func onBookClicked(_ shelfView: SectionShelfView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")
        
        modelData.readingBookInShelfId = bookId
        guard modelData.getSelectedReadingPosition() != nil else {
            //TODO
            return
        }
        modelData.presentingEBookReaderFromShelf = true
    }

    func onBookLongClicked(_ shelfView: SectionShelfView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")

        modelData.readingBookInShelfId = bookId
//        let detailMenuItem = UIMenuItem(title: "Details", action: #selector(onBookLongClickedDetailMenuItem(_:)))
//        UIMenuController.shared.menuItems = [detailMenuItem]
//        becomeFirstResponder()
//        UIMenuController.shared.showMenu(from: shelfView, rect: inShelfView)
        
        let bookDetailView = BookDetailView().environmentObject(modelData)
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
    
    @objc func onBookLongClickedDetailMenuItem(_ sender: Any?) {
        
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
