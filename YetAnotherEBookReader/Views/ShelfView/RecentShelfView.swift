//
//  RecentShelfView.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-22.
//

import SwiftUI
import KingfisherSwiftUI

struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}

fileprivate enum RecentShelfRenderItem: Identifiable {
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

fileprivate struct RecentShelfRow: Identifiable {
    let index: Int
    let items: [RecentShelfRenderItem]
    let adInsertion: ShelfAdInsertion?

    var id: Int { index }
}

@available(macCatalyst 14.0, *)
struct RecentShelfView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @ObservedObject var viewModel: RecentShelfViewModel
    @StateObject private var adStore = ShelfNativeAdStore()

    private func adLayoutContext(
        viewportHeight: CGFloat,
        containerWidth: CGFloat,
        columnCount: Int,
        isLoading: Bool,
        isEmpty: Bool
    ) -> ShelfAdLayoutContext {
        ShelfAdLayoutContext(
            viewportHeight: viewportHeight,
            containerWidth: containerWidth,
            columnCount: columnCount,
            isRegularWidth: horizontalSizeClass == .regular,
            isEditing: viewModel.selectionState.isEditing,
            isLoading: isLoading,
            isEmpty: isEmpty,
            capabilities: ShelfAdLayoutCapabilities(
                nativeAvailable: ShelfAdSlot.isNativeAvailable,
                bannerAvailable: ShelfAdSlot.isBannerAvailable
            )
        )
    }

    private func rowItems(
        from books: [ShelfBookItem],
        columnCount: Int,
        minimumRowCount: Int,
        endcapInsertions: [Int: ShelfAdInsertion]
    ) -> [RecentShelfRow] {
        guard columnCount > 0 else { return [] }

        var rows: [RecentShelfRow] = []
        var bookIndex = 0
        var rowIndex = 0

        while bookIndex < books.count || rowIndex < minimumRowCount {
            var rowAd = endcapInsertions[rowIndex]
            var rowCapacity = columnCount

            if case .nativeEndcap(_, let columnSpan) = rowAd?.kind {
                rowCapacity = max(0, columnCount - columnSpan)
                if books.count - bookIndex < rowCapacity {
                    rowAd = nil
                    rowCapacity = columnCount
                }
            }

            var items: [RecentShelfRenderItem] = []
            for columnIndex in 0..<rowCapacity {
                if bookIndex < books.count {
                    items.append(.book(books[bookIndex]))
                    bookIndex += 1
                } else {
                    items.append(.filler(id: "filler-\(rowIndex)-\(columnIndex)"))
                }
            }

            rows.append(RecentShelfRow(index: rowIndex, items: items, adInsertion: rowAd))
            rowIndex += 1
        }

        return rows
    }

    private func insertionMaps(_ insertions: [ShelfAdInsertion]) -> (
        endcapsByRow: [Int: ShelfAdInsertion],
        bannersAfterRow: [Int: ShelfAdInsertion]
    ) {
        var endcaps: [Int: ShelfAdInsertion] = [:]
        var banners: [Int: ShelfAdInsertion] = [:]

        for insertion in insertions {
            switch insertion.kind {
            case .nativeEndcap(let recentRow, _):
                endcaps[recentRow] = insertion
            case .adaptiveBanner(let afterContentRow):
                banners[afterContentRow] = insertion
            case .nativeStrip:
                break
            }
        }

        return (endcaps, banners)
    }

    @ViewBuilder
    private func shelfRow(_ row: RecentShelfRow, columnCount: Int, tileWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<row.items.count, id: \.self) { index in
                let item = row.items[index]
                let kind = ShelfLegacyLayout.tileKind(index: index, columnCount: columnCount)
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
                        },
                        onDelete: {
                            viewModel.deleteBook(bookId: book.id)
                        },
                        onGoodreads: {
                            viewModel.goodreadsAction(bookId: book.id)
                        },
                        onDouban: {
                            viewModel.doubanAction(bookId: book.id)
                        },
                        onHistory: {
                            viewModel.presentingHistoryBookId = book.id
                        }
                    )
                case .filler:
                    ShelfLegacyFillerTile(kind: kind, width: tileWidth)
                }
            }

            if let insertion = row.adInsertion,
               case .nativeEndcap(_, let columnSpan) = insertion.kind {
                ShelfAdSlot(
                    placement: .nativeEndcap(
                        width: CGFloat(columnSpan) * tileWidth,
                        slotID: insertion.slotID
                    ),
                    store: adStore
                )
                .frame(width: CGFloat(columnSpan) * tileWidth, height: ShelfLegacyMetrics.tileHeight)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ShelfLegacyMetrics.shelfBackgroundColor
                    .ignoresSafeArea()
                
                GeometryReader { geometry in
                    let containerWidth = geometry.size.width
                    let viewportHeight = max(1, geometry.size.height - ShelfLegacyMetrics.shelfTabBarExclusionHeight)
                    let books = viewModel.displayBooks
                    let shelfWidth = containerWidth
                    let columnCount = ShelfLegacyLayout.columnCount(containerWidth: shelfWidth)
                    let tileWidth = ShelfLegacyLayout.tileWidth(containerWidth: shelfWidth)
                    let minimumRowCount = max(1, Int(ceil(viewportHeight / ShelfLegacyMetrics.tileHeight)))
                    let adInsertions = ShelfAdLayoutPolicy.recentInsertions(
                        bookCount: books.count,
                        context: adLayoutContext(
                            viewportHeight: viewportHeight,
                            containerWidth: shelfWidth,
                            columnCount: columnCount,
                            isLoading: viewModel.loadedBooks == nil,
                            isEmpty: books.isEmpty
                        )
                    )
                    let insertionMaps = insertionMaps(adInsertions)
                    let rows = rowItems(
                        from: books,
                        columnCount: columnCount,
                        minimumRowCount: minimumRowCount,
                        endcapInsertions: insertionMaps.endcapsByRow
                    )

                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(rows) { row in
                                    shelfRow(row, columnCount: columnCount, tileWidth: tileWidth)

                                    if let insertion = insertionMaps.bannersAfterRow[row.index] {
                                        ShelfAdSlot(
                                            placement: .adaptiveBanner(
                                                width: shelfWidth,
                                                columnCount: columnCount,
                                                tileWidth: tileWidth,
                                                slotID: insertion.slotID
                                            ),
                                            store: adStore
                                        )
                                    }
                                }

                            }
                        }
                        .frame(width: shelfWidth)
                        .refreshable {
                            viewModel.refreshShelf()
                        }
                    }
                    .overlay(
                        Group {
                            if viewModel.loadedBooks == nil {
                                ProgressView("Loading Reading Progress...")
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor.systemBackground).opacity(0.8))
                                            .shadow(radius: 10)
                                    )
                                    .padding(32)
                            } else if viewModel.loadedBooks?.isEmpty == true {
                                VStack(spacing: 12) {
                                    Image(systemName: "books.vertical")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    Text("Your reading shelf is empty")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("Add books by star-toggling or downloading from Browse tab")
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
                                
                                Button(role: .destructive) {
                                    viewModel.activeAlert = .deleteConfirm(bookIds: viewModel.selectionState.selectedBookIds)
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete (\(viewModel.selectionState.selectedBookIds.count))")
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
            .navigationTitle("Recent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.selectionState.isEditing {
                        Button(action: { viewModel.refreshShelf() }) {
                            Image(systemName: "arrow.clockwise")
                        }
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
                case .missingFormat(let book, let format):
                    return Alert(
                        title: Text("Missing Format"),
                        message: Text("Try Download Now?"),
                        primaryButton: .default(Text("Download")) {
                            viewModel.triggerDownload(book: book, format: format)
                        },
                        secondaryButton: .cancel()
                    )
                case .downloadingFormat(let book, let format):
                    return Alert(
                        title: Text("Downloading Format"),
                        message: Text("Please wait a few moment"),
                        primaryButton: .default(Text("Restart")) {
                            viewModel.triggerDownload(book: book, format: format)
                        },
                        secondaryButton: .cancel(Text("Dismiss"))
                    )
                case .deleteConfirm(let bookIds):
                    return Alert(
                        title: Text("Delete Books?"),
                        message: Text("Will delete \(bookIds.count) books from reading shelf, are you sure?"),
                        primaryButton: .destructive(Text("Delete")) {
                            withAnimation {
                                viewModel.deleteSelectedBooks()
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
            .sheet(item: Binding<IdentifiableString?>(
                get: { viewModel.presentingHistoryBookId.map { IdentifiableString(value: $0) } },
                set: { viewModel.presentingHistoryBookId = $0?.value }
            )) { historyId in
                if let book = viewModel.container.bookManager.booksInShelf[historyId.value] {
                    NavigationView {
                        ReadingPositionHistoryView(
                            presenting: Binding<Bool>(
                                get: { viewModel.presentingHistoryBookId == historyId.value },
                                set: { isPresenting in
                                    if !isPresenting {
                                        viewModel.presentingHistoryBookId = nil
                                    }
                                }
                            ),
                            library: book.library,
                            bookId: book.id
                        )
                        .environment(\.appContainer, viewModel.container)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") {
                                    viewModel.presentingHistoryBookId = nil
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
