//
//  LibraryInfoView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import SwiftUI
import OSLog

@available(macCatalyst 14.0, *)
struct LibraryInfoView: View {
    @EnvironmentObject var modelData: ModelData

    @State private var selectedLibrary = "Calibre-Default"
    @State private var searchString = ""
    @State private var selectedBookIds = Set<Int32>()
    @State private var editMode: EditMode = .inactive

    private var defaultLog = Logger()
    
    var body: some View {
        VStack {
            
            HStack {
                Picker("Selected Library: \(selectedLibrary)", selection: $selectedLibrary) {
                    ForEach(modelData.libraryInfo.libraries) { library in
                        Text(library.id).tag(library.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onAppear() {
                    
                }
                .onChange(of: selectedLibrary) { value in
                    if( modelData.libraryInfo.libraryMap[selectedLibrary]!.booksMap.isEmpty ) {
                        syncLibrary()
                    }
                }
                
                Spacer()
                Button(action: { syncLibrary() }) {
                    Text("Sync")
                }
            }
            TextField("Search", text: $searchString, onCommit: {
                modelData.filteredBookList = modelData.libraryInfo.libraryMap[selectedLibrary]!.filterBooks(searchString).map { $0.id }
                if let index = modelData.filteredBookList.firstIndex(of: modelData.selectionLibraryNav ?? -1) {
                    modelData.currentBookId = modelData.filteredBookList[index]
                } else if !modelData.filteredBookList.isEmpty {
                    modelData.currentBookId = modelData.filteredBookList[0]
                }
            }).onAppear() {
                modelData.filteredBookList = modelData.libraryInfo.libraryMap[selectedLibrary]!.filterBooks(searchString).map { $0.id }
                if let index = modelData.filteredBookList.firstIndex(of: modelData.selectionLibraryNav ?? -1) {
                    modelData.currentBookId = modelData.filteredBookList[index]
                } else if !modelData.filteredBookList.isEmpty {
                    modelData.currentBookId = modelData.filteredBookList[0]
                }
            }
            .onDisappear() {
//                searchString = ""
//                modelData.libraryInfo.libraryMap[selectedLibrary]!.filterBooks(searchString)
            }
            
            NavigationView {
                List(selection: $selectedBookIds) {
//                    ForEach(modelData.libraryInfo.libraryMap[selectedLibrary]!.books.indices, id: \.self) { index in
                    ForEach(modelData.filteredBookList.filter({ (bookId) -> Bool in
                        modelData.libraryInfo.libraryMap[selectedLibrary]!.booksMap[bookId] != nil
                    }), id: \.self) { bookId in
                        NavigationLink(destination: BookDetailView(book: Binding<Book>(
                            get: {
//                                var book = library.books[index]
//                                if( !book.inShelf ) {
//                                    print("INSHELF \(library) \(library.books) \(index) \(book.title) \(book.inShelf)")
//                                }
//                                return modelData.libraryInfo.libraryMap[selectedLibrary]!.books[index]
                                modelData.libraryInfo.libraryMap[selectedLibrary]!.booksMap[bookId]!
                            },
                            set: { newBook in
                                modelData.libraryInfo.updateBook(book: newBook)
                            }
                        )), tag: bookId, selection: $modelData.selectionLibraryNav) {
                            if let book = modelData.libraryInfo.libraryMap[selectedLibrary]!.booksMap[bookId] {
                                VStack(alignment: .leading, spacing: 2) {
    //                                Text("\(modelData.libraryInfo.libraryMap[selectedLibrary]!.books[index].title)").font(.headline)
    //                                Text("\(modelData.libraryInfo.libraryMap[selectedLibrary]!.books[index].authors)").font(.subheadline)
                                    Text("\(book.title)").font(.headline)
                                    
                                    HStack {
                                        Text("\(book.authors)").font(.subheadline)
                                        Spacer()
                                        
                                        if book.formats["PDF"] != nil {
                                            Image("PDF").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20, alignment: .center)
                                        }
                                        if book.formats["EPUB"] != nil {
                                            Image("EPUB").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20, alignment: .center)
                                        }
                                        if book.inShelf {
                                            Image(systemName: "books.vertical")
                                        }
                                    }
                                }
                            }
                        }.isDetailLink(true)
                    }
                    .onDelete(perform: deleteFromList)
                }
                .navigationBarTitle("Pick a Book")
                .toolbar {
                    HStack {
                        if editMode == .active {
                            Button(action: {
                                defaultLog.info("selected \(selectedBookIds.description)")
                                selectedBookIds.forEach { bookId in
                                    var downloaded = false
                                    Book.Format.allCases.forEach {
                                        downloaded = downloaded || modelData.libraryInfo.downloadFormat(bookId, selectedLibrary, $0) { result in 
                                            
                                        }
                                    }
                                    if downloaded {
                                        modelData.libraryInfo.addToShelf(bookId, selectedLibrary)
                                    }
                                }
                                selectedBookIds.removeAll()
                            }
                            ) {
                                Image(systemName: "plus")
                            }
                            Button(action: {
                                defaultLog.info("selected \(selectedBookIds.description)")
                                selectedBookIds.forEach { bookId in
                                    Book.Format.allCases.forEach {
                                        modelData.libraryInfo.clearCache(bookId, selectedLibrary, $0)
                                    }
                                    modelData.libraryInfo.removeFromShelf(bookId, selectedLibrary)
                                }
                                selectedBookIds.removeAll()
                            }) {
                                Image(systemName: "trash")
                            }
                        }
                        editButton
                    }
                }
                .environment(\.editMode, self.$editMode)
            }
            .navigationViewStyle(DoubleColumnNavigationViewStyle())
            
        }
        
        VStack {
            
        }
    }
    
    private var editButton: some View {
        Button(action: {
            self.editMode.toggle()
            // self.selectedBookIds?.removeAll()
        }) {
            Text(self.editMode.title)
        }
    }
    
    private var addDelButton: some View {
            if editMode == .inactive {
                return Button(action: {}) {
                    Image(systemName: "plus")
                }
            } else {
                return Button(action: {}) {
                    Image(systemName: "trash")
                }
            }
        }

    
    func deleteFromList(at offsets: IndexSet) {
        modelData.filteredBookList.remove(atOffsets: offsets)
    }
    
    private func syncLibrary() {
        let endpointUrl = URL(string: modelData.calibreServer + "/cdb/cmd/list/0?library_id=" + selectedLibrary.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        let json:[Any] = [["title", "authors", "formats"], "", "", "", -1]
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            
            var request = URLRequest(url: endpointUrl)
            request.httpMethod = "POST"
            request.httpBody = data
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    // self.handleClientError(error)
                    defaultLog.warning("error: \(error.localizedDescription)")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode) else {
                    // self.handleServerError(response)
                    defaultLog.warning("not httpResponse: \(response.debugDescription)")
                    return
                }
                
                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                    let data = data,
                    let string = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            //self.webView.loadHTMLString(string, baseURL: url)
                            //result = string
                            handleLibraryBooks(json: data)
                        }
                    }
                }

            task.resume()
                    
        }catch{
        }
    }
    
    private func updateLibrary() {
        
    }
    
    func handleLibraryBooks(json: Data) {
        var booksMap = modelData.libraryInfo.libraryMap[selectedLibrary]!.booksMap
        
        do {
            let root = try JSONSerialization.jsonObject(with: json, options: []) as! NSDictionary
            let resultElement = root["result"] as! NSDictionary
            let bookIds = resultElement["book_ids"] as! NSArray
            
            bookIds.forEach { idNum in
                let id = (idNum as! NSNumber).int32Value
                if booksMap[id] == nil {
                    var book = Book(serverInfo: ServerInfo(calibreServer: modelData.calibreServer))
                    book.id = id
                    book.libraryName = selectedLibrary
                    booksMap[book.id] = book
                }
            }
            
            let dataElement = resultElement["data"] as! NSDictionary
            
            let titles = dataElement["title"] as! NSDictionary
            titles.forEach { (key, value) in
                let id = (key as! NSString).intValue
                let title = value as! String
                booksMap[id]!.title = title
            }
            
            let authors = dataElement["authors"] as! NSDictionary
            authors.forEach { (key, value) in
                let id = (key as! NSString).intValue
                let authors = value as! NSArray
                booksMap[id]!.authors = authors[0] as? String ?? "Unknown"
            }
            
            let formats = dataElement["formats"] as! NSDictionary
            formats.forEach { (key, value) in
                let id = (key as! NSString).intValue
                let formats = value as! NSArray
                formats.forEach { format in
                    booksMap[id]!.formats[(format as! String)] = ""
                }
            }
            
        } catch {
        
        }
        
        modelData.libraryInfo.libraryMap[selectedLibrary]!.updateBooks(booksMap)
        modelData.filteredBookList = modelData.libraryInfo.libraryMap[selectedLibrary]!.filterBooks(searchString).map{ $0.id }
    }
}

extension EditMode {
    var title: String {
        self == .active ? "Done" : "Select"
    }

    mutating func toggle() {
        self = self == .active ? .inactive : .active
    }
}

@available(macCatalyst 14.0, *)
struct LibraryInfoView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    @State static private var libraryInfo = LibraryInfo()
    static var previews: some View {
        LibraryInfoView()
            .environmentObject(ModelData())
    }
}
