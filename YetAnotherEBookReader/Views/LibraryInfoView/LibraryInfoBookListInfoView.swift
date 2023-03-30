//
//  LibraryInfoBookListInfoView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/30.
//

import SwiftUI

struct LibraryInfoBookListInfoView: View {
    @EnvironmentObject var modelData: ModelData
    
    @Binding var presenting: Bool
    
    var body: some View {
        NavigationView {
            List {
                ForEach(modelData.currentSearchLibraryResults
                    .map({ (modelData.calibreLibraries[$0.key.libraryId]!, $0.value) })
                    .sorted(by: { $0.0.id < $1.0.id}),
                        id: \.0.id) { searchResult in
                    Section {
                        HStack {
                            Text("Books")
                            Spacer()
                            Text("\(searchResult.1.totalNumber)")
                        }
                    } header: {
                        HStack {
                            Text(searchResult.0.name)
                            Spacer()
                            Text(searchResult.0.server.name)
                        }
                    } footer: {
                        HStack {
                            Spacer()
                            if searchResult.1.loading {
                                Text("Searching for more, result incomplete.")
                            } else if searchResult.1.error {
                                Text("Error occured, result incomplete.")
                            } else if searchResult.1.offlineResult,
                                      !searchResult.1.library.server.isLocal {
                                Text("Local cached result, may not up to date.")
                            }
                        }.font(.caption)
                            .foregroundColor(.red)
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
                        let searchCriteria = modelData.currentLibrarySearchCriteria
                        
//                                modelData.currentSearchLibraryResults
//                                    .filter {
//                                        $0.key.criteria == searchCriteria
//                                    }
//                                    .forEach {
//                                        modelData.librarySearchResetSubject.send($0.key)
//                                    }
//
//                                modelData.librarySearchResetSubject.send(.init(libraryId: "", criteria: searchCriteria))
//
//                                searchStringChanged(searchString: self.searchString)
//
//                                booksListInfoPresenting = false
                        
                        modelData.librarySearchManager.refreshSearchResult(libraryIds: modelData.filterCriteriaLibraries, searchCriteria: modelData.currentLibrarySearchCriteria)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct LibraryInfoBookListInfoView_Previews: PreviewProvider {
    @State static var presenting = true
    
    static var previews: some View {
        LibraryInfoBookListInfoView(presenting: $presenting)
    }
}
