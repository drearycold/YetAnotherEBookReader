//
//  SectionShelfController.swift
//  ShelfView_Example
//
//  Created by Adeyinka Adediji on 26/12/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import SwiftUI
import GoogleMobileAds

class SectionShelfController: UIViewController, SectionShelfViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var bookModel = [BookModel]()
    var shelfView: SectionShelfView!
    var bannerView: GADBannerView!

    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!
    
    func updateBookModel() {
        bookModel.removeAll()
        
        modelData.libraryInfo.libraries.forEach { library in
            print("LIBRARY \(library.name)")
            library.books.filter({ book in
                return book.inShelf
            }).forEach { book in
                let coverURL = "\(modelData!.calibreServer)/get/thumb/\(book.id)/\(book.libraryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)?sz=300x400"
                
                bookModel.append(
                    BookModel(
                        bookCoverSource: coverURL,
                        libraryName: book.libraryName,
                        bookId: book.id.description,
                        bookTitle: book.title))
            }
        }
        
        let bookModelSectionArray = [BookModelSection(sectionName: "Default", sectionId: "0", sectionBooks: bookModel)]
        self.shelfView.reloadBooks(bookModelSection: bookModelSectionArray)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shelfView.translatesAutoresizingMaskIntoConstraints = false
//        shelfView.leftAnchor.constraint(equalTo: motherView.leftAnchor, constant: 0).isActive = true
//        shelfView.rightAnchor.constraint(equalTo: motherView.rightAnchor, constant: 0).isActive = true
//        shelfView.topAnchor.constraint(equalTo: motherView.topAnchor, constant: 0).isActive = true
//        shelfView.bottomAnchor.constraint(equalTo: motherView.bottomAnchor, constant: 0).isActive = true
        

    }

    override func viewDidLoad() {
        super.viewDidLoad()

         modelData.libraryInfo.libraries.forEach { library in
            library.books.forEach { book in
                let coverURL = "\(modelData!.calibreServer)/get/thumb/\(book.id)/\(book.libraryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)?sz=300x400"
                
                bookModel.append(
                    BookModel(
                        bookCoverSource: coverURL,
                        libraryName: book.libraryName,
                        bookId: book.id.description,
                        bookTitle: book.title))
            }
        }
        
        let bookModelSectionArray = [BookModelSection(sectionName: "Default", sectionId: "0", sectionBooks: bookModel)]

        shelfView = SectionShelfView(frame: CGRect(x: 0, y: statusBarHeight, width: 350, height: 500), bookModelSection: bookModelSectionArray, bookSource: SectionShelfView.BOOK_SOURCE_URL)

        shelfView.delegate = self
//        motherView.addSubview(shelfView)
        //self.view = shelfView
        view.addSubview(shelfView)
        
        bannerView = GADBannerView(adSize: kGADAdSizeBanner)
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        bannerView.rootViewController = self
        bannerView.load(GADRequest())

        bannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerView)
        

        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: bannerView.topAnchor)
        ]) 
        
        view.addConstraints(
          [NSLayoutConstraint(item: bannerView,
                              attribute: .bottom,
                              relatedBy: .equal,
                              toItem: bottomLayoutGuide,
                              attribute: .top,
                              multiplier: 1,
                              constant: 0),
           NSLayoutConstraint(item: bannerView,
                              attribute: .centerX,
                              relatedBy: .equal,
                              toItem: view,
                              attribute: .centerX,
                              multiplier: 1,
                              constant: 0)
          ])
    }

    func onBookClicked(_ shelfView: SectionShelfView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")
        
        let bookDetailView = BookDetailView(
            book: modelData.getBook(libraryName: bookModel[index].libraryName, bookId: Int32(bookModel[index].bookId)!)).environmentObject(modelData)
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
    }
    
    func delay(_ delay: Double, closure: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
            execute: closure
        )
    }

}
