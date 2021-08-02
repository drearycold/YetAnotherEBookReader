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
    
    @State private var alertItem: AlertItem?
    
    @State private var batchDownloadSheetPresenting = false
    @State private var librarySwitcherPresenting = false
    
    private var defaultLog = Logger()
    
    var body: some View {
            NavigationView {
                VStack(alignment: .leading) {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack {
                            Button(action: {
                                modelData.syncLibrary(alertDelegate: self)
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            if modelData.calibreServerLibraryUpdating {
                                Text("\(modelData.calibreServerLibraryUpdatingProgress)/\(modelData.calibreServerLibraryUpdatingTotal)")
                            } else {
                                if modelData.calibreServerLibraryBooks.count > 1 {
                                    Text("\(modelData.calibreServerLibraryBooks.count) Books")
                                } else {
                                    Text("\(modelData.calibreServerLibraryBooks.count) Book")
                                }
                            }
                            
                            Spacer()
                            
                            Text(modelData.calibreServerUpdatingStatus ?? "")
                            filterMenuView()
                        }.onChange(of: modelData.calibreServerLibraryUpdating) { value in
                            //                            guard value == false else { return }
                            pageNo = 0
                        }
                        
                        TextField("Search", text: $searchString, onCommit: {
                            modelData.searchString = searchString
                            pageNo = 0
                        })
                        
                        Divider()
                    }.padding(4)    //top bar
                    
                    List(selection: $selectedBookIds) {
                        ForEach(modelData.filteredBookList.forPage(pageNo: pageNo, pageSize: pageSize), id: \.self) { bookId in
                            NavigationLink (
                                destination: BookDetailView(viewMode: .LIBRARY),
                                tag: bookId,
                                selection: $modelData.selectedBookId
                            ) {
                                LibraryInfoBookRow(bookId: bookId)
                            }
                            .isDetailLink(true)
                            .contextMenu {
                                if let book = modelData.calibreServerLibraryBooks[bookId] {
                                    bookRowContextMenuView(book: book)
                                }
                            }
                        }   //ForEach
//                        .onDelete(perform: deleteFromList)
                    }
                    .popover(isPresented: $batchDownloadSheetPresenting,
                             attachmentAnchor: .rect(.bounds),
                             arrowEdge: .top
                    ) {
                        LibraryInfoBatchDownloadSheet(presenting: $batchDownloadSheetPresenting, selectedBookIds: $selectedBookIds)
                    }
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Divider()
                        
                        HStack {
                            Button(action:{
                                librarySwitcherPresenting = true
                            }) {
                                Image(systemName: "arrow.left.arrow.right.circle")
                            }
                            .popover(isPresented: $librarySwitcherPresenting,
                                     attachmentAnchor: .rect(.bounds),
                                     arrowEdge: .top
                            ) {
                                LibraryInfoLibrarySwitcher(presenting: $librarySwitcherPresenting)
                                    .environmentObject(modelData)
                            }
                            
                            Spacer()
                            
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
                    }.padding(4)    //bottom bar
                }
                .padding(4)
                .navigationTitle(modelData.calibreLibraries[modelData.currentCalibreLibraryId]?.name ?? "Please Select a Library")
                .navigationBarTitleDisplayMode(.automatic)
                .statusBar(hidden: false)
//                .toolbar {
//                    toolbarContent()
//                }   //List.toolbar
                //.environment(\.editMode, self.$editMode)  //TODO
            }   //NavigationView
            .navigationViewStyle(DefaultNavigationViewStyle())
            .listStyle(PlainListStyle())
            .disabled(modelData.calibreServerUpdating || modelData.calibreServerLibraryUpdating)
            
        //Body
    }   //View
    
    private var editButton: some View {
        Button(action: {
            self.editMode.toggle()
            selectedBookIds.removeAll()
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

    @ViewBuilder
    private func bookRowContextMenuView(book: CalibreBook) -> some View {
        Menu("Download ...") {
            ForEach(book.formats.keys.compactMap{ Format.init(rawValue: $0) }, id:\.self) { format in
                Button(format.rawValue) {
                    modelData.clearCache(book: book, format: format)
                    modelData.downloadFormat(
                        book: book,
                        format: format
                    ) { success in
                        DispatchQueue.main.async {
                            if book.inShelf == false {
                                modelData.addToShelf(book.id, shelfName: book.tags.first ?? "Untagged")
                            }

                            if format == Format.EPUB {
                                removeFolioCache(book: book, format: format)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func filterMenuView() -> some View {
        Menu {
            Button(action: {
                modelData.filterCriteriaRating.removeAll()
                modelData.filterCriteriaFormat.removeAll()
                modelData.filterCriteriaIdentifier.removeAll()
                modelData.filterCriteriaShelved = .none
                modelData.filterCriteriaSeries.removeAll()
            }) {
                Text("Reset")
            }
            
            Menu("Shelved ...") {
                Button(action: {
                    if modelData.filterCriteriaShelved == .shelvedOnly {
                        modelData.filterCriteriaShelved = .none
                    } else {
                        modelData.filterCriteriaShelved = .shelvedOnly
                    }
                }, label: {
                    Text("Yes" + (modelData.filterCriteriaShelved == .shelvedOnly ? "✓" : ""))
                })
                Button(action: {
                    if modelData.filterCriteriaShelved == .notShelvedOnly {
                        modelData.filterCriteriaShelved = .none
                    } else {
                        modelData.filterCriteriaShelved = .notShelvedOnly
                    }
                }, label: {
                    Text("No" + (modelData.filterCriteriaShelved == .notShelvedOnly ? "✓" : ""))
                })
            }
            
            Menu("Series ...") {
                ForEach(
                    modelData.calibreServerLibraryBooks.values.reduce(
                        into: [String: Int]()) { result, value in
                        if value.series.isEmpty == false {
                            result[value.series] = 1
                        } else {
                            result["Without Series"] = 1
                        }
                    }
                    .compactMap { $0.key }
                    .sorted {
                        if $0 == "Without Series" {
                            return true
                        }
                        if $1 == "Without Series" {
                            return false
                        }
                        return $0 < $1
                    },
                    id: \.self) { id in
                    Button(action: {
                        if modelData.filterCriteriaSeries.contains(id) {
                            modelData.filterCriteriaSeries.remove(id)
                        } else {
                            modelData.filterCriteriaSeries.insert(id)
                        }
                    }, label: {
                        Text(id + (modelData.filterCriteriaSeries.contains(id) ? "✓" : ""))
                    })
                }
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
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        /*ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                Menu {
                    Button(action: {
                        modelData.filterCriteriaRating.removeAll()
                        modelData.filterCriteriaFormat.removeAll()
                        modelData.filterCriteriaIdentifier.removeAll()
                        modelData.filterCriteriaShelved = .none
                        modelData.filterCriteriaSeries.removeAll()
                    }) {
                        Text("Reset")
                    }
                    
                    Menu("Shelved ...") {
                        Button(action: {
                            if modelData.filterCriteriaShelved == .shelvedOnly {
                                modelData.filterCriteriaShelved = .none
                            } else {
                                modelData.filterCriteriaShelved = .shelvedOnly
                            }
                        }, label: {
                            Text("Yes" + (modelData.filterCriteriaShelved == .shelvedOnly ? "✓" : ""))
                        })
                        Button(action: {
                            if modelData.filterCriteriaShelved == .notShelvedOnly {
                                modelData.filterCriteriaShelved = .none
                            } else {
                                modelData.filterCriteriaShelved = .notShelvedOnly
                            }
                        }, label: {
                            Text("No" + (modelData.filterCriteriaShelved == .notShelvedOnly ? "✓" : ""))
                        })
                    }
                    
                    Menu("Series ...") {
                        ForEach(
                            modelData.calibreServerLibraryBooks.values.reduce(
                                into: [String: Int]()) { result, value in
                                if value.series.isEmpty == false {
                                    result[value.series] = 1
                                } else {
                                    result["Without Series"] = 1
                                }
                            }
                            .compactMap { $0.key }
                            .sorted {
                                if $0 == "Without Series" {
                                    return true
                                }
                                if $1 == "Without Series" {
                                    return false
                                }
                                return $0 < $1
                            },
                            id: \.self) { id in
                            Button(action: {
                                if modelData.filterCriteriaSeries.contains(id) {
                                    modelData.filterCriteriaSeries.remove(id)
                                } else {
                                    modelData.filterCriteriaSeries.insert(id)
                                }
                            }, label: {
                                Text(id + (modelData.filterCriteriaSeries.contains(id) ? "✓" : ""))
                            })
                        }
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
        }*/   //ToolbarItem
        ToolbarItem(placement: .navigationBarLeading) {
            HStack {
                //editButton
                if editMode == .active {
                    Button(action: {
                        guard selectedBookIds.isEmpty == false else { return }
                        
                        defaultLog.info("selected \(selectedBookIds.description)")
                        batchDownloadSheetPresenting = true
                        //selectedBookIds.removeAll()
                    }
                    ) {
                        Image(systemName: "star")
                    }
                    
                    Button(action: {
                        defaultLog.info("selected \(selectedBookIds.description)")
                        selectedBookIds.forEach { bookId in
                            Format.allCases.forEach {
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

extension LibraryInfoView : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

extension Array {
    func forPage(pageNo: Int, pageSize: Int) -> ArraySlice<Element> {
        guard pageNo*pageSize < count else { return [] }
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
