//
//  LibraryInfoBookListInfoView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/30.
//

import SwiftUI
import RealmSwift

struct LibraryInfoBookListInfoView: View {
    @EnvironmentObject var modelData: ModelData
    
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel

    @Binding var presenting: Bool
    
    var body: some View {
        NavigationView {
            List {
                if let result = viewModel.unifiedSearchResult {
                    ForEach(
                        result.unifiedOffsets
                            .sorted(by: { $0.key < $1.key })
                            .map({ unifiedOffset in
                                (
                                    unifiedOffset,
                                    modelData.calibreLibraries[unifiedOffset.key]
                                )
                            }), id: \.0.key) { searchResult in
                                if let library = searchResult.1 {
                                    let unifiedOffset = searchResult.0.value
                                    Section {
                                        HStack {
                                            Text("Offset")
                                            Spacer()
                                            Text("\(unifiedOffset.offset)")
                                        }
                                        #if DEBUG
                                        HStack {
                                            Text(unifiedOffset.searchObjectSource)
                                        }
                                        HStack {
                                            Text(unifiedOffset.generation.description)
                                            Spacer()
                                            Text(library.lastModified.description)
                                        }
                                        HStack {
                                            Text(unifiedOffset.offset.description)
                                            Text("/")
                                            Text(unifiedOffset.beenConsumed.description)
                                            Text("/")
                                            Text(unifiedOffset.beenCutOff.description)
                                        }
                                        #endif
                                    } header: {
                                        HStack {
                                            Text(library.name)
                                            Spacer()
                                            Text(library.server.name)
                                        }
                                    }
                                } else {
                                    Text("Error \(searchResult.0.key)")
                                }
                    }
                } else {
                    Text("No Search Result")
                }
            }
            .navigationTitle("Libraries")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        presenting = false
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        modelData.librarySearchManager.refreshSearchResults(libraryIds: viewModel.filterCriteriaLibraries, searchCriteria: viewModel.currentLibrarySearchCriteria)
                        
                        presenting = false
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

//struct LibraryInfoBookListInfoView_Previews: PreviewProvider {
//    @State static var presenting = true
//
//    static var previews: some View {
//        LibraryInfoBookListInfoView(presenting: $presenting)
//    }
//}
