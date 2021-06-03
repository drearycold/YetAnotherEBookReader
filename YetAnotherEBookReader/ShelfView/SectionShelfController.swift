//
//  SectionShelfController.swift
//  ShelfView_Example
//
//  Created by Adeyinka Adediji on 26/12/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import ShelfView_iOS
import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class SectionShelfController: UIViewController, SectionShelfViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var bookModel = [String: [BookModel]]()
    var shelfView: SectionShelfView!
#if canImport(GoogleMobileAds)
    var bannerView: GADBannerView!
#endif

    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!
    
    func updateBookModel() {
        /*
        bookModel = modelData.booksInShelf
            .sorted(
                by: { $0.value.title < $1.value.title } )
            .map { (key: String, value: CalibreBook) -> BookModel in
            BookModel(
                bookCoverSource: value.coverURL.absoluteString,
                bookId: key,
                bookTitle: value.title)
        }
        
        let bookModelSectionArray = [BookModelSection(sectionName: "Default", sectionId: "0", sectionBooks: bookModel)]
        self.shelfView.reloadBooks(bookModelSection: bookModelSectionArray)
         */
        
        bookModel = modelData.booksInShelf
            .filter { $0.value.library.server.isLocal == false}
            .sorted { $0.value.lastModified > $1.value.lastModified }
            .reduce(into: [String: [BookModel]]()) {
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
        var bookModelSectionArray = bookModel.sorted { $0.key < $1.key }.map {
            BookModelSection(sectionName: $0.key, sectionId: $0.key, sectionBooks: $0.value)
        }
        if bookModelSectionArray.isEmpty {
            bookModelSectionArray.append(BookModelSection(sectionName: "Default", sectionId: "Default", sectionBooks: []))
        }
        
        self.shelfView.reloadBooks(bookModelSection: bookModelSectionArray)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shelfView.translatesAutoresizingMaskIntoConstraints = false
//        shelfView.leftAnchor.constraint(equalTo: motherView.leftAnchor, constant: 0).isActive = true
//        shelfView.rightAnchor.constraint(equalTo: motherView.rightAnchor, constant: 0).isActive = true
//        shelfView.topAnchor.constraint(equalTo: motherView.topAnchor, constant: 0).isActive = true
//        shelfView.bottomAnchor.constraint(equalTo: motherView.bottomAnchor, constant: 0).isActive = true
        
        self.updateBookModel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        shelfView = SectionShelfView(frame: CGRect(x: 0, y: statusBarHeight, width: 350, height: 500), bookModelSection: [], bookSource: SectionShelfView.BOOK_SOURCE_URL)

        shelfView.delegate = self
//        motherView.addSubview(shelfView)
        //self.view = shelfView
        view.addSubview(shelfView)
        
        #if canImport(GoogleMobileAds)
        bannerView = GADBannerView()
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        bannerView.rootViewController = self
        bannerView.load(GADRequest())

        bannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerView)
        
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: bannerView.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: kGADAdSizeBanner.size.height / -2)
        ])
        bannerView.adSize = kGADAdSizeBanner
        #else
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        #endif
        
        updateBookModel()

    }

    func onBookClicked(_ shelfView: SectionShelfView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")
        
        modelData.readingBookInShelfId = bookId
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
