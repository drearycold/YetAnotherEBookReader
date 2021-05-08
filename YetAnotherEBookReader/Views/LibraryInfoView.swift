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
            NavigationView {
                
                List(selection: $selectedBookIds) {
                    TextField("Search", text: $searchString, onCommit: {
                        modelData.searchString = searchString
                        pageNo = 0
//                        if let index = modelData.filteredBookList.firstIndex(of: modelData.selectedBookId ?? -1) {
//                            modelData.currentBookId = modelData.filteredBookList[index]
//                        } else if !modelData.filteredBookList.isEmpty {
//                            modelData.currentBookId = modelData.filteredBookList[0]
//                        }
                    })
                    .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    
                    ForEach(modelData.filteredBookList.forPage(pageNo: pageNo, pageSize: pageSize), id: \.self) { bookId in
                        NavigationLink (
                            destination: BookDetailView(),
                            tag: bookId,
                            selection: $modelData.selectedBookId
                        ) {
                            if let book = modelData.calibreServerLibraryBooks[bookId] {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(book.title)").font(.headline)
                                    
                                    HStack {
                                        Text("\(book.authorsDescriptionShort)").font(.subheadline)
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
                .navigationTitle(modelData.calibreLibraries[modelData.currentCalibreLibraryId]!.name)
                .navigationBarTitleDisplayMode(.automatic)
                .statusBar(hidden: false)
                .toolbar {
                    toolbarContent()
                }   //List.toolbar
                .environment(\.editMode, self.$editMode)
            }   //NavigationView
            .onAppear() {
                //modelData.updateFilteredBookList()
//                if let index = modelData.filteredBookList.firstIndex(of: modelData.selectedBookId ?? -1) {
//                    modelData.currentBookId = modelData.filteredBookList[index]
//                } else if !modelData.filteredBookList.isEmpty {
//                    modelData.currentBookId = modelData.filteredBookList[0]
//                }
            }
            .navigationViewStyle(DefaultNavigationViewStyle())
        //Body
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

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
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
                            CalibreBook.Format.allCases.forEach {
                                downloaded = downloaded || modelData.downloadFormat(bookId, $0) { result in
                                    
                                }
                            }
                            if downloaded {
                                modelData.addToShelf(bookId)
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
                            CalibreBook.Format.allCases.forEach {
                                modelData.clearCache(inShelfId: modelData.calibreServerLibraryBooks[bookId]!.inShelfId, $0)
                            }
                            modelData.removeFromShelf(inShelfId: modelData.calibreServerLibraryBooks[bookId]!.inShelfId)
                        }
                        selectedBookIds.removeAll()
                    }) {
                        Image(systemName: "trash")
                    }
                }
                
            }
        }   //ToolbarItem
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
    static var previews: some View {
        LibraryInfoView()
            .environmentObject(ModelData())
    }
}
