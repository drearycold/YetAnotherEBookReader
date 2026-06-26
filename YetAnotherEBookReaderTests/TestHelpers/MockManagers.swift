//
//  MockManagers.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import Foundation
@testable import YetAnotherEBookReader

class MockServerManager: CalibreServerManager {
    var addServerCalled = false
    var addServerParam: (server: CalibreServer, libraries: [CalibreLibrary])?
    
    var removeServerCalled = false
    var removeServerParam: CalibreServer?
    
    override func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        addServerCalled = true
        addServerParam = (server, libraries)
        super.addServer(server: server, libraries: libraries)
    }
    
    override func removeServer(server: CalibreServer) async {
        removeServerCalled = true
        removeServerParam = server
        await super.removeServer(server: server)
    }
}

class MockLibraryManager: CalibreLibraryManager {
    var removeLibraryCalled = false
    var removeLibraryParam: CalibreLibrary?
    
    override func removeLibrary(library: CalibreLibrary) async {
        removeLibraryCalled = true
        removeLibraryParam = library
        await super.removeLibrary(library: library)
    }
}

class MockBookManager: CalibreBookManager {
    var addToShelfCalled = false
    var addToShelfBookParam: CalibreBook?
    var addToShelfFormatsParam: [Format]?
    
    var removeBookFromShelfCalled = false
    var removeBookFromShelfParam: String?
    
    override func addToShelf(book: CalibreBook, formats: [Format]) {
        addToShelfCalled = true
        addToShelfBookParam = book
        addToShelfFormatsParam = formats
        super.addToShelf(book: book, formats: formats)
    }
    
    override func removeFromShelf(inShelfId: String) {
        removeBookFromShelfCalled = true
        removeBookFromShelfParam = inShelfId
        super.removeFromShelf(inShelfId: inShelfId)
    }
}
