//
//  LibraryInfoBookListToolbar.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct LibraryInfoBookListDownloadButton: View {
    @ObservedObject var listViewModel: LibraryInfoBookListViewModel
    @ObservedObject var viewModel: UnifiedSearchViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        Button {
            listViewModel.prepareBatchDownload(books: viewModel.unifiedSearchResult?.books ?? [])
        } label: {
            Image(systemName: "square.and.arrow.down.on.square")
        }
        .disabled(viewModel.isSearchLoading)
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

struct LibraryInfoBookListSortMenu: View {
    @ObservedObject var libraryInfoViewModel: LibraryInfoView.ViewModel
    @ObservedObject var viewModel: UnifiedSearchViewModel
    
    var body: some View {
        Menu {
            ForEach(SortCriteria.allCases, id: \.self) { sort in
                Button(action: {
                    if libraryInfoViewModel.sortCriteria.by == sort {
                        libraryInfoViewModel.sortCriteria.ascending.toggle()
                    } else {
                        libraryInfoViewModel.sortCriteria.by = sort
                        libraryInfoViewModel.sortCriteria.ascending = sort == .Title ? true : false
                    }
                    libraryInfoViewModel.resetToFirstPage(searchViewModel: viewModel)
                }) {
                    HStack {
                        if libraryInfoViewModel.sortCriteria.by == sort {
                            if libraryInfoViewModel.sortCriteria.ascending {
                                Image(systemName: "arrow.down")
                            } else {
                                Image(systemName: "arrow.up")
                            }
                        } else {
                            Image(systemName: "arrow.down").hidden()
                        }
                        Text(sort.rawValue)
                    }
                }
            }
            
            if let result = viewModel.unifiedSearchResult,
               result.books.count == result.totalNumber,
               result.totalNumber > 0,
               result.totalNumber < 1000 {
                Divider()
                
                Text("Group By")
                
                ForEach(LibraryInfoView.GroupKey.allCases) { key in
                    Button {
                        if libraryInfoViewModel.sectionedBy != key {
                            libraryInfoViewModel.sectionedBy = key
                        } else {
                            libraryInfoViewModel.sectionedBy = nil
                        }
                    } label: {
                        Text((libraryInfoViewModel.sectionedBy == key ? "✓ " : "  ") + key.description)
                    }
                }
            } else {
                EmptyView()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}
