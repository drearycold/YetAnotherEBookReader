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

@available(macCatalyst 14.0, *)
struct RecentShelfView: View {
    @ObservedObject var viewModel: RecentShelfViewModel
    
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 20)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.displayBooks.isEmpty {
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
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(viewModel.displayBooks) { book in
                                    ShelfBookCard(
                                        book: book,
                                        isEditing: viewModel.selectionState.isEditing,
                                        isSelected: viewModel.selectionState.selectedBookIds.contains(book.id),
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
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(20)
                        }
                        .refreshable {
                            viewModel.refreshShelf()
                        }
                        
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
                        .environment(\.realmConfiguration, book.library.server.realmPerf.configuration)
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
