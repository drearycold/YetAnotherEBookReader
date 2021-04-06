//
//  ModelData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import Foundation
import Combine
import RealmSwift
import SwiftUI
import OSLog
import GoogleMobileAds

final class ModelData: ObservableObject {
    @Published var calibreServer = "http://calibre-server.lan:8080/"
    @Published var calibreUsername = ""
    @Published var calibrePassword = ""
    @Published var calibreLibrary = ""
    @Published var searchString = ""
    @Published var defaultFormat = Book.Format.PDF
    @Published var serverInfos = [ServerInfo]()
    @Published var libraryInfo = LibraryInfo()
    @Published var filteredBookList = [Int32]()
    
    var calibreServerDescription: String {
        return "\(calibreUsername)@\(calibreServer)"
    }
    
    var currentBookId: Int32 = -1 {
            didSet {
                self.selectionLibraryNav = currentBookId
            }
        }

    @Published var selectionLibraryNav: Int32? = nil
    
    private var defaultLog = Logger()
    
    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        
        let realm = try! Realm(
            configuration: Realm.Configuration(
                schemaVersion: 5,
                migrationBlock: { migration, oldSchemaVersion in
                        if oldSchemaVersion < 5 {
                            // if you added a new property or removed a property you don't
                            // have to do anything because Realm automatically detects that
                        }
                    }
            )
        )
        
        
        
        let inShelf = realm.objects(BookRealm.self)
        print("In Shelf \(inShelf.count)")
        inShelf.forEach { bookRealm in
            let library = libraryInfo.getLibrary(name: bookRealm.libraryName)
            print(self.libraryInfo.libraries.count)
            var book = library.booksMap[bookRealm.id]
            if( book == nil) {
                book = Book(serverInfo: ServerInfo(calibreServer: calibreServer))
                book!.id = bookRealm.id
                book!.authors = bookRealm.authors
                book!.libraryName = library.name
                book!.title = bookRealm.title
                book!.comments = bookRealm.comments
                book!.inShelf = true
                if bookRealm.formatsData != nil {
                    book!.formats = try! JSONSerialization.jsonObject(with: bookRealm.formatsData! as Data, options: []) as! [String: String]
                }
//                library!.booksMap[book!.id] = book
                libraryInfo.updateBook(book: book!)
            }
            // libraryInfo.libraryMap[bookRealm.libraryName] = library
            print(self.libraryInfo.libraryMap[bookRealm.libraryName]!.booksMap.count)
        }
//        for var library in libraryInfo.libraryMap.values {
//            library.filterBooks("")
//            libraryInfo.libraryMap[library.name] = library
//        }
        libraryInfo.regenArray()
        
        switch UIDevice.current.userInterfaceIdiom {
            case .phone:
                defaultFormat = Book.Format.EPUB
            case .pad:
                defaultFormat = Book.Format.PDF
            default:
                defaultFormat = Book.Format.EPUB
        }
    }
    
    func getLibrary() -> Library? {
        return libraryInfo.libraryMap[calibreLibrary]
    }
    
    func updateFilteredBookList(searchString: String?) {
        if searchString != nil {
            self.searchString = searchString!
        }
        filteredBookList = getLibrary()?.filterBooks(self.searchString).map { $0.id } ?? []
    }
    
    func getBook(libraryName: String, bookId: Int32) -> Binding<Book> {

        return Binding<Book>(
            get: {
                let libraryInfo = self.libraryInfo
                let library = libraryInfo.libraryMap[libraryName]!
                guard let book = self.libraryInfo.libraryMap[libraryName]!.booksMap[bookId] else {
//                    if let (index, _) = self.libraryInfo.libraryMap[libraryName]!.books.map({ abs($0.id - bookId) }).enumerate().minElement({ $0.1 < $1.1 }) {
//                        let result = self.libraryInfo.libraryMap[libraryName]!.books[index]
//                    }
                    if let minDiffIndex = library.books.map({ (book) -> Int32 in
                        abs(book.id - bookId)
                    }).enumerated().min(by: { (lhs, rhs) -> Bool in
                        lhs.element < rhs.element
                    }) {
                        return library.books[minDiffIndex.offset]
                    }
                    return Book(serverInfo: ServerInfo(calibreServer: "DELETED"), title: "DELETED", authors: "DELETED")
                }
                print("GET inShelf \(book.inShelf)")
                //return self.libraryInfo.libraryMap[libraryName]!.booksMap[bookId]!
                return book
            },
            set: { newBook in
                let libraryInfo = self.libraryInfo
                print("before updateBook")
                print(self.libraryInfo.libraryMap[newBook.libraryName]!.booksMap[newBook.id]!.readPos.getDevices().count)
                print(newBook.readPos.getDevices().count)
                print(self.libraryInfo.libraryMap[newBook.libraryName]!.booksMap[newBook.id]!.inShelf)
                print(newBook.inShelf)
                self.libraryInfo.updateBook(book: newBook)
                print("after updateBook")
                print(self.libraryInfo.libraryMap[newBook.libraryName]!.booksMap[newBook.id]!.readPos.getDevices().count)
                print(newBook.readPos.getDevices().count)
                print(self.libraryInfo.libraryMap[newBook.libraryName]!.booksMap[newBook.id]!.inShelf)
                print(newBook.inShelf)
            }
        )
    }

    func updateStoreReadingPosition(enabled: Bool, value: String) {
        //TODO
    }
    
    func updateCustomDictViewer(enabled: Bool, value: String) {
        //TODO
    }
}

func load<T: Decodable>(_ filename: String) -> T {
    let data: Data
    
    guard let file = Bundle.main.url(forResource: filename, withExtension: nil)
    else {
        fatalError("Couldn't find \(filename) in main bundle.")
    }
    
    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }
    
    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error)")
    }
}

class ConfigurationRealm: Object {
    @objc dynamic var id: Int32 = 0
    @objc dynamic var libraryName = ""
    @objc dynamic var title = ""
    @objc dynamic var authors = ""
    @objc dynamic var comments = ""
    @objc dynamic var formatsData: NSData?
}
