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

@available(macCatalyst 14.0, *)
struct RecentShelfView: View {
    @ObservedObject var viewModel: RecentShelfViewModel
    
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
                    let totalTileCount = ShelfLegacyLayout.viewportTileCount(
                        itemCount: viewModel.displayBooks.count,
                        columnCount: columnCount,
                        viewportHeight: viewportHeight
                    )
                    
                    let books = viewModel.displayBooks
                    let fillerCount = max(0, totalTileCount - books.count)
                    
                    let renderItems: [RecentShelfRenderItem] = {
                        var items = books.map { RecentShelfRenderItem.book($0) }
                        for i in 0..<fillerCount {
                            items.append(.filler(id: "filler-\(i)"))
                        }
                        return items
                    }()
                    
                    let gridColumns = Array(repeating: GridItem(.fixed(tileWidth), spacing: 0), count: columnCount)
                    
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 0) {
                            ForEach(0..<renderItems.count, id: \.self) { index in
                                let item = renderItems[index]
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
                        }
                    }
                    .refreshable {
                        viewModel.refreshShelf()
                    }
                    .overlay(
                        Group {
                            if !viewModel.container.bookManager.isShelfLoaded {
                                ProgressView("Loading Reading Progress...")
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor.systemBackground).opacity(0.8))
                                            .shadow(radius: 10)
                                    )
                                    .padding(32)
                            } else if books.isEmpty {
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
                        }
                    }
                }
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
                        .environmentObject(viewModel.container)
                        .environmentObject(viewModel.container.downloadManager)
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
                        .environmentObject(viewModel.container)
                        .environment(\.realmConfiguration, book.library.server.realm(in: viewModel.container).configuration)
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
