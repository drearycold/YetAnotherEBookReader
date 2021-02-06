//
//  PlainShelfController.swift
//  ShelfView
//
//  Created by tdscientist on 09/23/2017.
//  Copyright (c) 2017 tdscientist. All rights reserved.
//

// import ShelfView
import SwiftUI
import RealmSwift

class PlainShelfController: UIViewController, PlainShelfViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var bookModel = [BookModel]()
    var shelfView: PlainShelfView!
    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!

    func updateBookModel() {
        bookModel.removeAll()
        
        modelData.libraryInfo.libraryMap.values.forEach { library in
            print("LIBRARY \(library.name)")
            library.booksMap.values.filter({ book in
                print("BOOK \(book.title) \(book.inShelf)")
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
        
        self.shelfView.reloadBooks(bookModel: bookModel)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shelfView.translatesAutoresizingMaskIntoConstraints = false
        // shelfView.leftAnchor.constraint(equalTo: motherView.leftAnchor, constant: 0).isActive = true
        // shelfView.rightAnchor.constraint(equalTo: motherView.rightAnchor, constant: 0).isActive = true
        // shelfView.topAnchor.constraint(equalTo: motherView.topAnchor, constant: 0).isActive = true
        // shelfView.bottomAnchor.constraint(equalTo: motherView.bottomAnchor, constant: 0).isActive = true
        
        updateBookModel()
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
        
        shelfView = PlainShelfView(frame: CGRect(x: 0, y: statusBarHeight, width: 350, height: 500), bookModel: bookModel, bookSource: PlainShelfView.BOOK_SOURCE_URL)
        
        shelfView.delegate = self
        // motherView.addSubview(shelfView)
        self.view = shelfView
    }

    func onBookClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        let book = modelData.getBook(libraryName: bookModel[index].libraryName, bookId: Int32(bookModel[index].bookId)!)
        let detailView = UIBookDetailView(
            rootView: BookDetailView(book: modelData.getBook(libraryName: bookModel[index].libraryName, bookId: Int32(bookModel[index].bookId)!))
        )
        detailView.shelf = self
        
        self.present(detailView, animated: true, completion: nil)
    }

    func delay(_ delay: Double, closure: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
            execute: closure
        )
    }
    
}

class UIBookDetailView : UIHostingController<BookDetailView> {
    
    var shelf: PlainShelfController!
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            shelf.updateBookModel()
        }
    }
}
