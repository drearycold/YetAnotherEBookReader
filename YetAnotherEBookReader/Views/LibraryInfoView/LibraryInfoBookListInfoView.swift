//
//  LibraryInfoBookListInfoView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/30.
//

import SwiftUI

struct LibraryInfoBookListInfoView: View {
    @Environment(\.appContainer) var container
    
    @EnvironmentObject var viewModel: UnifiedSearchViewModel

    @Binding var presenting: Bool
    
    var body: some View {
        NavigationView {
            List {
                if let result = viewModel.unifiedSearchResult {
                    ForEach(listedLibraryIds(result), id: \.self) { libraryId in
                        if let library = container.libraryManager.calibreLibraries[libraryId] {
                            let status = viewModel.libraryStatuses[libraryId]
                            Section {
                                if let failure = status?.failure {
                                    Text(status?.fromCache == true ? "Showing saved results. \(failure.message)" : failure.message)
                                        .foregroundColor(.secondary)
                                }
                                if let unifiedOffset = result.unifiedOffsets[libraryId] {
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
                                }
                            } header: {
                                HStack {
                                    Text(library.name)
                                    Spacer()
                                    Text(library.server.name)
                                }
                            }
                        } else {
                            Text("Error \(libraryId)")
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
                        viewModel.resetSearch(force: true)
                        
                        presenting = false
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    /// The libraries in the merged result, and those whose search failed without a cache to show.
    private func listedLibraryIds(_ result: UnifiedSearchResult) -> [String] {
        let failedLibraryIds = viewModel.libraryStatuses.filter { $0.value.failure != nil }.keys
        return Set(result.unifiedOffsets.keys).union(failedLibraryIds).sorted()
    }
}

//struct LibraryInfoBookListInfoView_Previews: PreviewProvider {
//    @State static var presenting = true
//
//    static var previews: some View {
//        LibraryInfoBookListInfoView(presenting: $presenting)
//    }
//}
