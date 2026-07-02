//
//  SectionShelfView.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-22.
//

import SwiftUI
import KingfisherSwiftUI

fileprivate enum SectionShelfRenderItem: Identifiable {
    case book(ShelfBookItem)
    case filler(id: String)
    
    var id: String {
        switch self {
        case .book(let book):
            return book.id
        case .filler(let id):
            return id
        }
    }
}

@available(macCatalyst 14.0, *)
struct SectionShelfView: View {
    @ObservedObject var viewModel: SectionShelfViewModel
    
    private func rowTileKind(index: Int, totalCount: Int) -> ShelfTileKind {
        if index == 0 {
            return .left
        } else if index == totalCount - 1 {
            return .right
        } else {
            return .center
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ShelfLegacyMetrics.shelfBackgroundColor
                    .ignoresSafeArea()
                
                GeometryReader { geometry in
                    let containerWidth = geometry.size.width
                    let viewportHeight = geometry.size.height
                    let columnCount = ShelfLegacyLayout.columnCount(containerWidth: containerWidth)
                    let tileWidth = ShelfLegacyLayout.tileWidth(containerWidth: containerWidth)
                    
                    let sections = viewModel.displaySections
                    let currentHeight = CGFloat(sections.count) * 232.0
                    let remainingHeight = viewportHeight - currentHeight
                    let fillerRowCount = remainingHeight > 0 ? Int(ceil(remainingHeight / 200.0)) : 0
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sections) { section in
                                VStack(spacing: 0) {
                                    ShelfLegacySectionHeader(title: section.title)
                                    
                                    let books = section.books
                                    
                                    if books.count <= columnCount {
                                        let totalTileCount = ShelfLegacyLayout.completedTileCount(
                                            itemCount: books.count,
                                            columnCount: columnCount
                                        )
                                        let fillerCount = max(0, totalTileCount - books.count)
                                        let renderItems: [SectionShelfRenderItem] = {
                                            var items = books.map { SectionShelfRenderItem.book($0) }
                                            for i in 0..<fillerCount {
                                                items.append(.filler(id: "filler-\(section.id)-\(i)"))
                                            }
                                            return items
                                        }()
                                        
                                        HStack(spacing: 0) {
                                            ForEach(0..<renderItems.count, id: \.self) { index in
                                                let item = renderItems[index]
                                                let kind = rowTileKind(index: index, totalCount: totalTileCount)
                                                switch item {
                                                case .book(let book):
                                                    ShelfBookCard(
                                                        book: book,
                                                        isEditing: viewModel.selectionState.isEditing,
                                                        isSelected: viewModel.selectionState.selectedBookIds.contains(book.id),
                                                        tileKind: kind,
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
                                                    ShelfLegacyFillerTile(kind: kind, width: tileWidth)
                                                }
                                            }
                                        }
                                        .frame(height: 200)
                                    } else {
                                        let totalTileCount = books.count
                                        let renderItems = books.map { SectionShelfRenderItem.book($0) }
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 0) {
                                                ForEach(0..<renderItems.count, id: \.self) { index in
                                                    let item = renderItems[index]
                                                    let kind = rowTileKind(index: index, totalCount: totalTileCount)
                                                    switch item {
                                                    case .book(let book):
                                                        ShelfBookCard(
                                                            book: book,
                                                            isEditing: viewModel.selectionState.isEditing,
                                                            isSelected: viewModel.selectionState.selectedBookIds.contains(book.id),
                                                            tileKind: kind,
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
                                                        ShelfLegacyFillerTile(kind: kind, width: tileWidth)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(height: 200)
                                    }
                                }
                            }
                            
                            ForEach(0..<fillerRowCount, id: \.self) { rowIndex in
                                HStack(spacing: 0) {
                                    ForEach(0..<columnCount, id: \.self) { index in
                                        let kind = rowTileKind(index: index, totalCount: columnCount)
                                        ShelfLegacyFillerTile(kind: kind, width: tileWidth)
                                    }
                                }
                                .frame(height: 200)
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.refreshShelf()
                    }
                    .overlay(
                        Group {
                            if sections.isEmpty && !viewModel.isInitialLoadComplete {
                                ProgressView("Loading Discover Shelf...")
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor.systemBackground).opacity(0.8))
                                            .shadow(radius: 10)
                                    )
                                    .padding(32)
                            } else if sections.isEmpty && viewModel.isInitialLoadComplete {
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
                        }
                    }
                }
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
                        .environmentObject(viewModel.container)
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
