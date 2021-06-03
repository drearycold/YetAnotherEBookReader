//
//  PlainShelfController.swift
//  ShelfView
//
//  Created by tdscientist on 09/23/2017.
//  Copyright (c) 2017 tdscientist. All rights reserved.
//

import ShelfView_iOS
import SwiftUI
import FolioReaderKit

class PlainShelfController: UIViewController, PlainShelfViewDelegate {
    let statusBarHeight = UIApplication.shared.statusBarFrame.height
    var books = [CalibreBook]()
    var bookModel = [BookModel]()
    var shelfView: PlainShelfView!
    // @IBOutlet var motherView: UIView!
    var modelData: ModelData!

    override var canBecomeFirstResponder: Bool {
        true
    }
    
    func updateBookModel() {
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
        shelfView.translatesAutoresizingMaskIntoConstraints = false
        // shelfView.leftAnchor.constraint(equalTo: motherView.leftAnchor, constant: 0).isActive = true
        // shelfView.rightAnchor.constraint(equalTo: motherView.rightAnchor, constant: 0).isActive = true
        // shelfView.topAnchor.constraint(equalTo: motherView.topAnchor, constant: 0).isActive = true
        // shelfView.bottomAnchor.constraint(equalTo: motherView.bottomAnchor, constant: 0).isActive = true
        
        updateBookModel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        shelfView = PlainShelfView(frame: CGRect(x: 0, y: statusBarHeight, width: 350, height: 500), bookModel: bookModel, bookSource: PlainShelfView.BOOK_SOURCE_URL)
        
        shelfView.delegate = self
        updateBookModel()
        // motherView.addSubview(shelfView)
        self.view = shelfView
    }

    func onBookClicked(_ shelfView: PlainShelfView, index: Int, bookId: String, bookTitle: String) {
        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index)")
        
        modelData.readingBookInShelfId = bookId
        modelData.updatedReadingPosition = modelData.getLatestReadingPosition() ?? modelData.getInitialReadingPosition()
        
        modelData.presentingEBookReaderForPlainShelf = true

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
