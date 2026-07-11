//
//  LibraryInfoBookListView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/28.
//

import SwiftUI
import KingfisherSwiftUI
import OSLog

struct LibraryInfoBookListView: View {
    @Environment(\.appContainer) var container
    @EnvironmentObject var libraryInfoViewModel: LibraryInfoView.ViewModel
    @EnvironmentObject var viewModel: UnifiedSearchViewModel

    @StateObject private var listViewModel = LibraryInfoBookListViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    headerView(geometry: geometry)
                    
                    Divider()
                    
                    contentView(geometry: geometry)
                    
                    Divider()
                    
                    footerView(geometry: geometry)
                }
                
                if viewModel.isSearchLoading {
                    ProgressView()
                        .scaleEffect(4, anchor: .center)
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
        }
        .onAppear {
            listViewModel.bindDownloadSnapshots(container: container)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.browse.book-list")
    }
    
    @ViewBuilder
    private func headerView(geometry: GeometryProxy) -> some View {
        LibraryInfoBookListHeader(
            listViewModel: listViewModel,
            libraryInfoViewModel: libraryInfoViewModel,
            viewModel: viewModel,
            geometry: geometry
        )
    }
    
    @ViewBuilder
    private func contentView(geometry: GeometryProxy) -> some View {
        LibraryInfoBookListContent(
            listViewModel: listViewModel,
            libraryInfoViewModel: libraryInfoViewModel,
            viewModel: viewModel,
            container: container,
            geometry: geometry
        )
    }
    
    @ViewBuilder
    private func footerView(geometry: GeometryProxy) -> some View {
        LibraryInfoBookListFooter(
            listViewModel: listViewModel,
            libraryInfoViewModel: libraryInfoViewModel,
            viewModel: viewModel,
            container: container,
            geometry: geometry
        )
    }
}
