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

    @ObservedRealmObject var unifiedSearchObject: CalibreUnifiedSearchObject
    
    @Binding var presenting: Bool
    
    var body: some View {
        NavigationView {
            List {
                ForEach(
                    unifiedSearchObject.unifiedOffsets
                        .sorted(by: { $0.key < $1.key })
                        .map({ unifiedOffset in
                            (
                                unifiedOffset,
                                modelData.calibreLibraries[unifiedOffset.key]
                            )
                        }), id: \.0.key) { searchResult in
                            if let unifiedOffset = searchResult.0.value,
                               let searchObjectSource = unifiedOffset.searchObjectSource,
                               let sourceObjOpt = unifiedOffset.searchObject?.sources[searchObjectSource],
                               let sourceObj = sourceObjOpt,
                               let library = searchResult.1 {
                            Section {
                                HStack {
                                    Text("Books")
                                    Spacer()
                                    Text("\(sourceObj.totalNumber)")
                                }
                                #if DEBUG
                                HStack {
                                    Text(searchObjectSource)
                                }
                                HStack {
                                    Text(sourceObj.generation.description)
                                    Spacer()
                                    Text(library.lastModified.description)
                                }
                                HStack {
                                    Text(unifiedOffset.offset.description)
                                    Text("/")
                                    Text(unifiedOffset.beenConsumed.description)
                                    Text("/")
                                    Text(unifiedOffset.beenCutOff.description)

                                    Spacer()

                                    Text(sourceObj.books.count.description)
                                    Text("/")
                                    Text(sourceObj.bookIds.count.description)
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
                        modelData.librarySearchManager.refreshSearchResult(libraryIds: viewModel.filterCriteriaLibraries, searchCriteria: viewModel.currentLibrarySearchCriteria)
                        
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
