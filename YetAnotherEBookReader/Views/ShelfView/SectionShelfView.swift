//
//  SectionShelfView.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-22.
//

import SwiftUI
import KingfisherSwiftUI

@available(macCatalyst 14.0, *)
struct SectionShelfView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @ObservedObject var viewModel: SectionShelfViewModel
    @StateObject private var adStore = ShelfNativeAdStore()

    @ViewBuilder
    private func shelfTile(_ tile: ShelfTilePlan, tileWidth: CGFloat) -> some View {
        switch tile.content {
        case .book(let book):
            ShelfBookCard(
                book: book,
                isEditing: viewModel.selectionState.isEditing,
                isSelected: viewModel.selectionState.selectedBookIds.contains(book.id),
                tileKind: tile.kind,
                tileWidth: tileWidth,
                onTap: {
                    viewModel.tapBook(bookId: book.id)
                },
                onLongPress: {
                    if !viewModel.selectionState.isEditing {
                        viewModel.tapBook(bookId: book.id)
                    }
                },
                onDetails: {
                    viewModel.presentingBookDetailId = book.id
                },
                onRefresh: {
                    viewModel.refreshBookFormats(bookId: book.id)
                }
            )
        case .filler:
            ShelfLegacyFillerTile(kind: tile.kind, width: tileWidth)
        }
    }

    @ViewBuilder
    private func sectionView(
        _ section: DiscoverShelfSectionPlan,
        tileWidth: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ShelfLegacySectionHeader(title: section.title)

            switch section.layoutMode {
            case .fixed:
                HStack(spacing: 0) {
                    ForEach(section.tiles) { tile in
                        shelfTile(tile, tileWidth: tileWidth)
                    }
                }
                .frame(height: ShelfLegacyMetrics.tileHeight)
            case .horizontalScroll:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(section.tiles) { tile in
                            shelfTile(tile, tileWidth: tileWidth)
                        }
                    }
                }
                .frame(height: ShelfLegacyMetrics.tileHeight)
            }
        }
    }

    @ViewBuilder
    private func layoutElement(
        _ element: DiscoverShelfLayoutElement,
        geometry: ShelfLayoutGeometry
    ) -> some View {
        switch element {
        case .section(let section):
            sectionView(section, tileWidth: geometry.tileWidth)
        case .ad(let insertion):
            switch insertion.kind {
            case .nativeStrip:
                ShelfAdSlot(
                    placement: .nativeStrip(
                        width: geometry.shelfWidth,
                        slotID: insertion.slotID
                    ),
                    store: adStore
                )
            case .adaptiveBanner:
                ShelfAdSlot(
                    placement: .adaptiveBanner(
                        width: geometry.shelfWidth,
                        columnCount: geometry.columnCount,
                        tileWidth: geometry.tileWidth,
                        slotID: insertion.slotID
                    ),
                    store: adStore
                )
            case .nativeEndcap:
                EmptyView()
            }
        case .fillerRow(let row):
            HStack(spacing: 0) {
                ForEach(row.tiles) { tile in
                    shelfTile(tile, tileWidth: geometry.tileWidth)
                }
            }
            .frame(height: ShelfLegacyMetrics.tileHeight)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ShelfLegacyMetrics.shelfBackgroundColor
                    .ignoresSafeArea()

                GeometryReader { geometry in
                    let input = ShelfLayoutInput(
                        containerSize: geometry.size,
                        bottomExclusionHeight: ShelfLegacyMetrics.shelfTabBarExclusionHeight,
                        widthClass: horizontalSizeClass == .regular ? .regular : .compact,
                        isEditing: viewModel.selectionState.isEditing,
                        isLoading: !viewModel.isInitialLoadComplete,
                        adCapabilities: ShelfAdLayoutCapabilities(
                            nativeAvailable: ShelfAdSlot.isNativeAvailable,
                            bannerAvailable: ShelfAdSlot.isBannerAvailable
                        )
                    )
                    let plan = ShelfLayoutPlanner.discover(
                        sections: viewModel.displaySections,
                        input: input
                    )

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(plan.elements) { element in
                                layoutElement(element, geometry: plan.geometry)
                            }

                        }
                    }
                    .frame(width: plan.geometry.shelfWidth)
                    .refreshable {
                        await viewModel.refreshShelf()
                    }
                    .overlay(
                        Group {
                            if viewModel.displaySections.isEmpty && !viewModel.isInitialLoadComplete {
                                ProgressView("Loading Discover Shelf...")
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor.systemBackground).opacity(0.8))
                                            .shadow(radius: 10)
                                    )
                                    .padding(32)
                            } else if viewModel.displaySections.isEmpty && viewModel.isInitialLoadComplete {
                                VStack(spacing: 12) {
                                    Image(systemName: "books.vertical")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    Text("No recommendations available")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("Configure calibre servers in Settings to download books")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(UIColor.systemBackground).opacity(0.8))
                                        .shadow(radius: 10)
                                )
                                .padding(32)
                            }
                        }
                    )
                    .safeAreaInset(edge: .bottom) {
                        if viewModel.selectionState.isEditing {
                            HStack {
                                Button("Select All") {
                                    withAnimation {
                                        viewModel.selectAllBooks()
                                    }
                                }
                                .font(.headline)

                                Spacer()

                                Button {
                                    viewModel.activeAlert = .downloadConfirm(bookIds: viewModel.selectionState.selectedBookIds)
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("Download (\(viewModel.selectionState.selectedBookIds.count))")
                                    }
                                }
                                .font(.headline)
                                .disabled(viewModel.selectionState.selectedBookIds.isEmpty)

                                Spacer()

                                Button("Clear") {
                                    withAnimation {
                                        viewModel.clearSelection()
                                    }
                                }
                                .font(.headline)
                            }
                            .padding()
                            .background(
                                Color(.secondarySystemGroupedBackground)
                                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -4)
                            )
                            .transition(.move(edge: .bottom))
                        } else {
                            Color.clear
                                .frame(height: ShelfLegacyMetrics.shelfTabBarExclusionHeight + 16)
                        }
                    }
                }
            }
            .onDisappear {
                adStore.clear()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button("Reset Filters") {
                            viewModel.resetLibraryFilters()
                        }
                        Divider()
                        ForEach(viewModel.libraryFilters) { filter in
                            Button(action: {
                                viewModel.toggleLibraryFilter(libraryId: filter.id)
                            }) {
                                HStack {
                                    Text(filter.name + " on " + filter.serverName)
                                    if filter.isSelected {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Libraries")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.selectionState.isEditing {
                        Button {
                            Task {
                                await viewModel.refreshShelf()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isRefreshing)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation {
                            viewModel.selectionState.isEditing.toggle()
                            if !viewModel.selectionState.isEditing {
                                viewModel.selectionState.selectedBookIds.removeAll()
                            }
                        }
                    }) {
                        Text(viewModel.selectionState.isEditing ? "Done" : "Edit")
                    }
                }
            }
            .alert(item: $viewModel.activeAlert) { alertType in
                switch alertType {
                case .downloadConfirm(let bookIds):
                    return Alert(
                        title: Text("Download Books?"),
                        message: Text("Will add \(bookIds.count) books to reading shelf, are you sure?"),
                        primaryButton: .default(Text("Download")) {
                            withAnimation {
                                viewModel.downloadSelectedBooks()
                            }
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .sheet(item: Binding<IdentifiableString?>(
                get: { viewModel.presentingBookDetailId.map { IdentifiableString(value: $0) } },
                set: { viewModel.presentingBookDetailId = $0?.value }
            )) { detailId in
                NavigationView {
                    BookDetailView(bookId: detailId.value, viewMode: .SHELF)
                        .environment(\.appContainer, viewModel.container)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") {
                                    viewModel.presentingBookDetailId = nil
                                }
                            }
                        }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            viewModel.bootstrapIfDatabaseReady()
        }
    }
}
