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

final class ModelData: ObservableObject {
    @Published var calibreServer = "http://calibre-server.lan:8080/"
    @Published var libraryInfo = LibraryInfo()
    
    var isReading = false
    
    init() {
        let realm = try! Realm(configuration: Realm.Configuration(schemaVersion: 2))
        
        let inShelf = realm.objects(BookRealm.self)
        print("In Shelf \(inShelf.count)")
        inShelf.forEach { bookRealm in
            var library = libraryInfo.libraryMap[bookRealm.libraryName]
            if( library == nil ) {
                library = libraryInfo.addLibrary(name: bookRealm.libraryName)
            }
            print(self.libraryInfo.libraries.count)
            var book = library!.booksMap[bookRealm.id]
            if( book == nil) {
                book = Book(serverInfo: ServerInfo(calibreServer: calibreServer))
                book!.id = bookRealm.id
                book!.libraryName = library!.name
                book!.title = bookRealm.title
                book!.comments = bookRealm.comments
                book!.inShelf = true
                if bookRealm.formatsData != nil {
                    book!.formats = try! JSONSerialization.jsonObject(with: bookRealm.formatsData! as Data, options: []) as! [String: String]
                }
                library!.booksMap[book!.id] = book
            }
            libraryInfo.libraryMap[bookRealm.libraryName] = library
            print(self.libraryInfo.libraryMap[bookRealm.libraryName]!.booksMap.count)
        }
        for var library in libraryInfo.libraryMap.values {
            library.filterBooks("")
            libraryInfo.libraryMap[library.name] = library
        }
        libraryInfo.regenArray()
    }
    
    func getBook(libraryName: String, bookId: Int32) -> Binding<Book> {

        return Binding<Book>(
            get: {
                let libraryInfo = self.libraryInfo
                print("GET inShelf \(self.libraryInfo.libraryMap[libraryName]!.booksMap[bookId]!.inShelf)")
                return self.libraryInfo.libraryMap[libraryName]!.booksMap[bookId]!
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
