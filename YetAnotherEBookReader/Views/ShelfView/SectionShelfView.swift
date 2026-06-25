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
    @ObservedObject var viewModel: SectionShelfViewModel
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.displaySections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No libraries available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Configure calibre servers in Settings to download books")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(viewModel.displaySections) { section in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(section.title)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 20)
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 16) {
                                                ForEach(section.books) { book in
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
                                                        }
                                                    )
                                                }
                                            }
                                            .padding(.horizontal, 20)
                                        }
                                        .frame(height: 240)
                                    }
                                }
                            }
                            .padding(.vertical, 20)
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
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
