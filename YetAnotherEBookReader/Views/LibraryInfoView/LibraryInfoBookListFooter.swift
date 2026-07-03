//
//  LibraryInfoBookListFooter.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct LibraryInfoBookListFooter: View {
    @ObservedObject var listViewModel: LibraryInfoBookListViewModel
    @ObservedObject var libraryInfoViewModel: LibraryInfoView.ViewModel
    @ObservedObject var viewModel: UnifiedSearchViewModel
    let container: AppContainer
    let geometry: GeometryProxy
    
    var body: some View {
        HStack {
            Button {
                listViewModel.booksListInfoPresenting = true
            } label: {
                Image(systemName: "info.circle")
            }
            .popover(isPresented: $listViewModel.booksListInfoPresenting) {
                LibraryInfoBookListInfoView(presenting: $listViewModel.booksListInfoPresenting)
                    .frame(idealWidth: geometry.size.width - 50, idealHeight: geometry.size.height - 50)
            }
            .padding([.leading, .trailing], 4)

            Text(libraryInfoViewModel.getLibrarySearchingText(container: container, searchResult: viewModel.unifiedSearchResult, libraryStatuses: viewModel.libraryStatuses))
            
            if viewModel.isSearchLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            
            Spacer()
            
            if let result = viewModel.unifiedSearchResult, result.totalNumber > 0 {
                Text("\(result.books.count) / \(result.totalNumber)")
            }
            
            Button {
                viewModel.resetSearch(force: true)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .padding(4)
    }
}
