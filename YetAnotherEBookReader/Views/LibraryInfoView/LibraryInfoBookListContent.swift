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
            let books = viewModel.unifiedSearchResult?.books ?? []
            let bookIds = books.map(\.inShelfId)

            List {
                #if DEBUG
                debugView()
                #endif
                
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
            .onChange(of: bookIds) { _ in
                listViewModel.pruneBatchDownloadSelection(books: books)
            }
            .disabled(viewModel.isSearchLoading)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !listViewModel.isBatchSelectionMode {
                        LibraryInfoBookListDownloadButton(
                            listViewModel: listViewModel,
                            viewModel: viewModel
                        )
                        .disabled(viewModel.isSearchLoading || books.isEmpty)
                    }
                    
                    LibraryInfoBookListSortMenu(
                        libraryInfoViewModel: libraryInfoViewModel,
                        viewModel: viewModel
                    )
                    .disabled(viewModel.isSearchLoading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if listViewModel.isBatchSelectionMode {
                    batchSelectionBar(books: books)
                }
            }
            .popover(isPresented: $listViewModel.batchDownloadSheetPresenting,
                     attachmentAnchor: .point(.bottom),
                     arrowEdge: .bottom
            ) {
                LibraryInfoBatchDownloadSheet(
                    presenting: $listViewModel.batchDownloadSheetPresenting,
                    downloadBookList: $listViewModel.downloadBookList
                )
                .frame(idealWidth: geometry.size.width - 50, idealHeight: geometry.size.height - 50)
            }
        }
    }

    @ViewBuilder
    private func batchSelectionBar(books: [CalibreBook]) -> some View {
        HStack {
            Button("Select All") {
                listViewModel.selectAllBatchDownloadBooks(books: books)
            }
            .font(.headline)

            Spacer()

            Button {
                listViewModel.prepareSelectedBatchDownload(books: books)
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Download (\(listViewModel.selectedBatchDownloadBookIds.count))")
                }
            }
            .font(.headline)
            .disabled(listViewModel.selectedBatchDownloadBookIds.isEmpty)

            Spacer()

            Button("Clear") {
                listViewModel.clearBatchDownloadSelection()
            }
            .font(.headline)
            .disabled(listViewModel.selectedBatchDownloadBookIds.isEmpty)

            Spacer()

            Button("Cancel") {
                listViewModel.cancelBatchSelectionMode()
            }
            .font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -4)
        )
    }
    
    @ViewBuilder
    private func listEntryView(book: CalibreBook, index: Int) -> some View {
        Group {
            if listViewModel.isBatchSelectionMode {
                batchSelectionEntryView(book: book, index: index)
            } else if container.bookManager.bookExists(forPrimaryKey: book.inShelfId) {
                NavigationLink {
                    BookDetailView(bookId: book.inShelfId, viewMode: .LIBRARY)
                        .onAppear {
                            container.bookManager.selectedBookId = book.inShelfId
                        }
                } label: {
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

    @ViewBuilder
    private func batchSelectionEntryView(book: CalibreBook, index: Int) -> some View {
        Button {
            listViewModel.toggleBatchDownloadSelection(book: book)
        } label: {
            HStack(spacing: 8) {
                let isSelected = listViewModel.selectedBatchDownloadBookIds.contains(book.inShelfId)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 28)

                LibraryInfoBookRow(book: book, index: index, activeDownload: listViewModel.activeDownload(for: book)) {
                    onRowAppear(index: index)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func onRowAppear(index: Int) {
        guard let result = viewModel.unifiedSearchResult else { return }
        guard index + 1 > result.limitNumber - 20 else { return }
        viewModel.expandSearchUnifiedBookLimit()
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
