//
//  LibraryInfoBookListContent.swift
//  YetAnotherEBookReader
//

import SwiftUI
import OSLog

struct LibraryInfoBookListContent: View {
    @ObservedObject var listViewModel: LibraryInfoBookListViewModel
    @ObservedObject var libraryInfoViewModel: LibraryInfoView.ViewModel
    @ObservedObject var viewModel: UnifiedSearchViewModel
    let container: AppContainer
    let geometry: GeometryProxy
    
    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $listViewModel.selectedBookIds) {
                #if DEBUG
                debugView()
                #endif
                
                let books = viewModel.unifiedSearchResult?.books ?? []
                if books.isEmpty {
                    Text(libraryInfoViewModel.getLibraryLoadingCount(container: container, searchResult: viewModel.unifiedSearchResult, libraryStatuses: viewModel.libraryStatuses) > 0 ? "Loading books..." : "Found no books.")
                } else {
                    let sections = listViewModel.buildSections(books: books, sectionedBy: libraryInfoViewModel.sectionedBy)
                    ForEach(sections) { section in
                        if section.title.isEmpty {
                            ForEach(section.items) { item in
                                listEntryView(book: item.book, index: item.index)
                            }
                        } else {
                            Section {
                                ForEach(section.items) { item in
                                    listEntryView(book: item.book, index: item.index)
                                }
                            } header: {
                                Text(section.title)
                            }
                        }
                    }
                }
                #if DEBUG
                debugView()
                #endif
            }
            .onAppear {
                print("LIBRARYINFOVIEW books=\(viewModel.unifiedSearchResult?.books.count ?? 0)")
            }
            .disabled(viewModel.isSearchLoading)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    LibraryInfoBookListDownloadButton(
                        listViewModel: listViewModel,
                        viewModel: viewModel,
                        geometry: geometry
                    )
                    .disabled(viewModel.isSearchLoading)
                    
                    LibraryInfoBookListSortMenu(
                        libraryInfoViewModel: libraryInfoViewModel,
                        viewModel: viewModel
                    )
                    .disabled(viewModel.isSearchLoading)
                }
            }
        }
    }
    
    @ViewBuilder
    private func listEntryView(book: CalibreBook, index: Int) -> some View {
        Group {
            if container.bookManager.bookExists(forPrimaryKey: book.inShelfId) {
                NavigationLink (
                    destination: BookDetailView(bookId: book.inShelfId, viewMode: .LIBRARY),
                    tag: book.inShelfId,
                    selection: selectedBookIdBinding
                ) {
                    LibraryInfoBookRow(book: book, index: index, activeDownload: listViewModel.activeDownload(for: book)) {
                        onRowAppear(index: index)
                    }
                }
                .isDetailLink(true)
                .contextMenu {
                    LibraryInfoBookContextMenu(
                        book: book,
                        listViewModel: listViewModel,
                        libraryInfoViewModel: libraryInfoViewModel,
                        viewModel: viewModel,
                        container: container
                    )
                }
            } else {
                LibraryInfoBookRow(book: book, index: index, activeDownload: listViewModel.activeDownload(for: book)) {
                    onRowAppear(index: index)
                }
                .contextMenu {
                    LibraryInfoBookContextMenu(
                        book: book,
                        listViewModel: listViewModel,
                        libraryInfoViewModel: libraryInfoViewModel,
                        viewModel: viewModel,
                        container: container
                    )
                }
            }
        }
    }
    
    private func onRowAppear(index: Int) {
        guard let result = viewModel.unifiedSearchResult else { return }
        guard index + 1 > result.limitNumber - 20 else { return }
        viewModel.expandSearchUnifiedBookLimit()
    }

    private var selectedBookIdBinding: Binding<String?> {
        Binding(
            get: { container.bookManager.selectedBookId },
            set: { container.bookManager.selectedBookId = $0 }
        )
    }
    
    @ViewBuilder
    private func debugView() -> some View {
        Group {
            if let result = viewModel.unifiedSearchResult {
                Group {
                    Text("Object: \(result.libraryIds.count) \(result.unifiedOffsets.count)")
                    
                    Text("Books: \(result.books.count), Total: \(result.totalNumber), Limit: \(result.limitNumber)")
                    
                    Button {
                        viewModel.expandSearchUnifiedBookLimit()
                    } label: {
                        Text("Expand")
                    }
                    
                    Button {
                        viewModel.resetSearch(force: false)
                    } label: {
                        Text("Reset")
                    }
                }
                
                ForEach(container.libraryManager.calibreLibraries
                    .sorted(by: { $0.key < $1.key })
                    .filter({
                        $0.value.hidden == false
                        &&
                        $0.value.server.removed == false
                        &&
                        (result.libraryIds.isEmpty || result.libraryIds.contains($0.key))
                    }), id: \.key
                ) { libraryId, library in
                    Text("Required: \(libraryId)")
                    if let unifiedOffset = result.unifiedOffsets[libraryId] {
                        HStack {
                            Text("Loading: \(viewModel.libraryStatuses[libraryId]?.loading == true ? 1 : 0)")
                            Text("offset: \(unifiedOffset.offset)")
                        }
                    } else {
                        Text("No Unified Offset Object")
                     }
                }
            } else {
                Text("No Unified Search Result")
            }
        }
        .foregroundColor(.red)
    }
}
