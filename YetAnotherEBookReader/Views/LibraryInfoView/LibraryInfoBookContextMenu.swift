//
//  LibraryInfoBookContextMenu.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct LibraryInfoBookContextMenu: View {
    let book: CalibreBook
    @ObservedObject var listViewModel: LibraryInfoBookListViewModel
    @ObservedObject var libraryInfoViewModel: LibraryInfoView.ViewModel
    @ObservedObject var viewModel: UnifiedSearchViewModel
    @ObservedObject var modelData: ModelData
    
    var body: some View {
        let authors = listViewModel.filterableAuthors(for: book, filterCriteriaCategory: libraryInfoViewModel.filterCriteriaCategory)
        if !authors.isEmpty {
            Menu("More by Author ...") {
                ForEach(authors, id: \.self) { author in
                    Button {
                        listViewModel.updateFilterCategoryAction(
                            key: "Authors",
                            value: author,
                            libraryInfoViewModel: libraryInfoViewModel,
                            searchViewModel: viewModel
                        )
                    } label: {
                        Text(author)
                    }
                }
            }
        }
        
        let tags = listViewModel.filterableTags(for: book, filterCriteriaCategory: libraryInfoViewModel.filterCriteriaCategory)
        if !tags.isEmpty {
            Menu("More of Tags ...") {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        listViewModel.updateFilterCategoryAction(
                            key: "Tags",
                            value: tag,
                            libraryInfoViewModel: libraryInfoViewModel,
                            searchViewModel: viewModel
                        )
                    } label: {
                        Text(tag)
                    }
                }
            }
        }
        
        if listViewModel.shouldShowSeriesFilter(for: book, filterCriteriaCategory: libraryInfoViewModel.filterCriteriaCategory) {
            Button {
                listViewModel.updateFilterSeriesAction(
                    series: book.series,
                    libraryInfoViewModel: libraryInfoViewModel,
                    searchViewModel: viewModel
                )
            } label: {
                Text("More in Series: \(book.series)")
            }
        }
        
        Menu("Download ...") {
            ForEach(book.formats.keys.compactMap{ Format.init(rawValue: $0) }, id:\.self) { format in
                Button {
                    listViewModel.downloadOrAddToShelfAction(book: book, format: format, modelData: modelData)
                } label: {
                    Text(
                        format.rawValue
                        + "\t\t\t"
                        + ByteCountFormatter.string(
                            fromByteCount: Int64(book.formats[format.rawValue]?.serverSize ?? 0),
                            countStyle: .file
                        )
                    )
                }
            }
        }
    }
}
