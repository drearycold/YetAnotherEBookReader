//
//  LibraryInfoView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import SwiftUI
import OSLog
import Combine

@available(macCatalyst 14.0, *)
struct LibraryInfoView: View {
    @EnvironmentObject var modelData: ModelData

    @State private var searchString = ""
    @State private var selectedBookIds = Set<Int32>()
    @State private var editMode: EditMode = .inactive
    @State private var pageNo = 0
    @State private var pageSize = 100
    @State private var updater = 0
    
    var pageNoProxy: Binding<String> {
        Binding<String>(
            get: { String(format: "%d", self.pageNo) },
            set: {
                if let value = NumberFormatter().number(from: $0) {
                    self.pageNo = value.intValue
                }
            }
        )
    }
    
    private var defaultLog = Logger()
    
    var body: some View {
        
        
        VStack {
            TextField("Search", text: $searchString, onCommit: {
                modelData.updateFilteredBookList(searchString: searchString)
                pageNo = 0
                if let index = modelData.filteredBookList.firstIndex(of: modelData.selectionLibraryNav ?? -1) {
                    modelData.currentBookId = modelData.filteredBookList[index]
                } else if !modelData.filteredBookList.isEmpty {
                    modelData.currentBookId = modelData.filteredBookList[0]
                }
            })
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            
            NavigationView {
                List(selection: $selectedBookIds) {
//                    ForEach(modelData.libraryInfo.libraryMap[selectedLibrary]!.books.indices, id: \.self) { index in
                    ForEach(modelData.filteredBookList.forPage(pageNo: pageNo, pageSize: pageSize).filter({ (bookId) -> Bool in
                        var result = false
                        if let library = modelData.getLibrary() {
                            result = library.booksMap[bookId] != nil
                        }
                        return result
                    })
                    , id: \.self) { bookId in
                        NavigationLink(destination: BookDetailView(book: Binding<Book>(
                            get: {
//                                var book = library.books[index]
//                                if( !book.inShelf ) {
//                                    print("INSHELF \(library) \(library.books) \(index) \(book.title) \(book.inShelf)")
//                                }
//                                return modelData.libraryInfo.libraryMap[selectedLibrary]!.books[index]
                                if let library = modelData.getLibrary(), let book = library.booksMap[bookId] {
                                    return book
                                }
                                var book = Book(serverInfo: ServerInfo(calibreServer: modelData.calibreServer))
                                book.id = bookId
                                book.libraryName = modelData.calibreLibrary
                                return book
                            },
                            set: { newBook in
                                modelData.libraryInfo.updateBook(book: newBook)
                            }
                        )), tag: bookId, selection: $modelData.selectionLibraryNav) {
                            if let library = modelData.getLibrary(), let book = library.booksMap[bookId] {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(book.title)").font(.headline)
                                    
                                    HStack {
                                        Text("\(book.authors)").font(.subheadline)
                                        Spacer()
                                        if book.rating > 9 {
                                            Text("★★★★★").font(.subheadline)
                                        } else if book.rating > 7 {
                                            Text("★★★★").font(.subheadline)
                                        } else if book.rating > 5 {
                                            Text("★★★").font(.subheadline)
                                        } else if book.rating > 3 {
                                            Text("★★").font(.subheadline)
                                        } else if book.rating > 1 {
                                            Text("★").font(.subheadline)
                                        } else {
                                            Text("☆").font(.subheadline)
                                        }
                                        
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
                    }   //ForEach
                    .onDelete(perform: deleteFromList)
                }   //List
                .navigationTitle("Pick a Book")
                .navigationBarTitleDisplayMode(.automatic)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button(action:{
                                if pageNo > 10 {
                                    pageNo -= 10
                                } else {
                                    pageNo = 0
                                }
                            }) {
                                Image(systemName: "chevron.backward.2")
                            }
                            Button(action:{
                                if pageNo > 0 {
                                    pageNo -= 1
                                }
                            }) {
                                Image(systemName: "chevron.backward")
                            }
                            Text("\(pageNo+1) / \(Int((Double(modelData.filteredBookList.count) / Double(pageSize)).rounded(.up)))")
                            Button(action:{
                                if ((pageNo + 1) * pageSize) < modelData.filteredBookList.count {
                                    pageNo += 1
                                }
                            }) {
                                Image(systemName: "chevron.forward")
                            }
                            Button(action:{
                                for i in stride(from:10, to:1, by:-1) {
                                    if ((pageNo + i) * pageSize) < modelData.filteredBookList.count {
                                        pageNo += i
                                        break
                                    }
                                }
                            }) {
                                Image(systemName: "chevron.forward.2")
                            }
                        }
                    }   //ToolbarItem
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack {
                            editButton
                            if editMode == .active {
                                Button(action: {
                                    defaultLog.info("selected \(selectedBookIds.description)")
                                    selectedBookIds.forEach { bookId in
                                        var downloaded = false
                                        Book.Format.allCases.forEach {
                                            downloaded = downloaded || modelData.libraryInfo.downloadFormat(bookId, modelData.calibreLibrary, $0) { result in
                                                
                                            }
                                        }
                                        if downloaded {
                                            modelData.libraryInfo.addToShelf(bookId, modelData.calibreLibrary)
                                        }
                                    }
                                    selectedBookIds.removeAll()
                                }
                                ) {
                                    Image(systemName: "star")
                                }
                                Button(action: {
                                    defaultLog.info("selected \(selectedBookIds.description)")
                                    selectedBookIds.forEach { bookId in
                                        Book.Format.allCases.forEach {
                                            modelData.libraryInfo.clearCache(bookId, modelData.calibreLibrary, $0)
                                        }
                                        modelData.libraryInfo.removeFromShelf(bookId, modelData.calibreLibrary)
                                    }
                                    selectedBookIds.removeAll()
                                }) {
                                    Image(systemName: "trash")
                                }
                            }
                            
                        }
                    }   //ToolbarItem
                }   //List.toolbar
                .environment(\.editMode, self.$editMode)
            }   //NavigationView
            .onAppear() {
                modelData.updateFilteredBookList(searchString: searchString)
                if let index = modelData.filteredBookList.firstIndex(of: modelData.selectionLibraryNav ?? -1) {
                    modelData.currentBookId = modelData.filteredBookList[index]
                } else if !modelData.filteredBookList.isEmpty {
                    modelData.currentBookId = modelData.filteredBookList[0]
                }
            }
            .onChange(of: modelData.calibreLibrary) { value in
//                if( modelData.getLibrary().booksMap.isEmpty ) {
//                    syncLibrary()
//                }
                pageNo = 0
                modelData.updateFilteredBookList(searchString: searchString)
            }
            .onChange(of: modelData.selectionLibraryNav, perform: { value in
                
            })
            .navigationViewStyle(DefaultNavigationViewStyle())
        }   //Body
    }   //View
    
    private var editButton: some View {
        Button(action: {
            self.editMode.toggle()
            // self.selectedBookIds?.removeAll()
        }) {
            //Text(self.editMode.title)
            Image(systemName: self.editMode.systemName)
        }
    }
    
    private var addDelButton: some View {
            if editMode == .inactive {
                return Button(action: {}) {
                    Image(systemName: "star")
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
    
    
}

extension Array {
    func forPage(pageNo: Int, pageSize: Int) -> ArraySlice<Element> {
        return self[(pageNo*pageSize) ..< Swift.min((pageNo+1)*pageSize, count)]
    }
}

extension EditMode {
    var title: String {
        self == .active ? "Done" : "Select"
    }
    
    var systemName: String {
        self == .active ? "xmark.circle" : "checkmark.circle"
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
