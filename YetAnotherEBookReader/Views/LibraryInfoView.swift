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
                                        Text(book.ratingDescription).font(.subheadline)
                                    }
                                
                                    HStack {
                                        if book.inShelf {
                                            Image(systemName: "books.vertical")
                                        } else {
                                            Image(systemName: "books.vertical")
                                                .hidden()
                                        }
                                        if book.identifiers["goodreads"] != nil {
                                            Image("icon-goodreads")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                        } else {
                                            Image("icon-goodreads")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                                .hidden()
                                        }
                                        if book.identifiers["amazon"] != nil {
                                            Image("icon-amazon")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                        } else {
                                            Image("icon-amazon")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                                .hidden()
                                        }
                                        Spacer()
                                        if book.formats["PDF"] != nil {
                                            Image("PDF")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                        } else {
                                            Image("PDF")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                                .hidden()
                                        }
                                        
                                        if book.formats["EPUB"] != nil {
                                            Image("EPUB")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                        } else {
                                            Image("EPUB")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 20, height: 20, alignment: .center)
                                                .hidden()
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
                Menu {
                    Button(action: {
                        modelData.filterCriteriaRating.removeAll()
                        modelData.filterCriteriaFormat.removeAll()
                        modelData.filterCriteriaIdentifier.removeAll()
                    }) {
                        Text("Reset")
                    }
                    Menu("Rating ...") {
                        ForEach(modelData.calibreServerLibraryBooks.values.reduce(into: [String: Int](), { result, value in
                            result[value.ratingDescription] = 1
                        }).compactMap { $0.key }.sorted(), id: \.self) { id in
                            Button(action: {
                                if modelData.filterCriteriaRating.contains(id) {
                                    modelData.filterCriteriaRating.remove(id)
                                } else {
                                    modelData.filterCriteriaRating.insert(id)
                                }
                            }, label: {
                                Text(id + (modelData.filterCriteriaRating.contains(id) ? "✓" : ""))
                            })
                        }
                    }
                    Menu("Format ...") {
                        ForEach(modelData.calibreServerLibraryBooks.values.reduce(into: [String: Int](), { result, value in
                            value.formats.forEach { result[$0.key] = 1 }
                        }).compactMap { $0.key }.sorted(), id: \.self) { id in
                            Button(action: {
                                if modelData.filterCriteriaFormat.contains(id) {
                                    modelData.filterCriteriaFormat.remove(id)
                                } else {
                                    modelData.filterCriteriaFormat.insert(id)
                                }
                            }, label: {
                                Text(id + (modelData.filterCriteriaFormat.contains(id) ? "✓" : ""))
                            })
                        }
                    }
                    Menu("Linked with ...") {
                        ForEach(modelData.calibreServerLibraryBooks.values.reduce(into: [String: Int](), { result, value in
                            value.identifiers.forEach { result[$0.key] = 1 }
                        }).compactMap { $0.key }.sorted(), id: \.self) { id in
                            Button(action: {
                                if modelData.filterCriteriaIdentifier.contains(id) {
                                    modelData.filterCriteriaIdentifier.remove(id)
                                } else {
                                    modelData.filterCriteriaIdentifier.insert(id)
                                }
                            }, label: {
                                Text(id + (modelData.filterCriteriaIdentifier.contains(id) ? "✓" : ""))
                            })
                        }
                    }
                } label: {
                    Image(systemName: "line.horizontal.3.decrease.circle")
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
                                downloaded = downloaded || modelData.downloadFormat(book: modelData.calibreServerLibraryBooks[bookId]!, format: $0) { result in
                                    
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
