//
//  ShelfBookCard.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-22.
//

import SwiftUI
import KingfisherSwiftUI

struct ShelfBookCard: View {
    let book: ShelfBookItem
    let isEditing: Bool
    let isSelected: Bool
    let tileKind: ShelfTileKind
    let tileWidth: CGFloat
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDetails: () -> Void
    let onRefresh: () -> Void
    var onDelete: (() -> Void)? = nil
    var onGoodreads: (() -> Void)? = nil
    var onDouban: (() -> Void)? = nil
    var onHistory: (() -> Void)? = nil
    
    init(
        book: ShelfBookItem,
        isEditing: Bool,
        isSelected: Bool,
        tileKind: ShelfTileKind = .center,
        tileWidth: CGFloat = 150,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        onDetails: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onGoodreads: (() -> Void)? = nil,
        onDouban: (() -> Void)? = nil,
        onHistory: (() -> Void)? = nil
    ) {
        self.book = book
        self.isEditing = isEditing
        self.isSelected = isSelected
        self.tileKind = tileKind
        self.tileWidth = tileWidth
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onDetails = onDetails
        self.onRefresh = onRefresh
        self.onDelete = onDelete
        self.onGoodreads = onGoodreads
        self.onDouban = onDouban
        self.onHistory = onHistory
    }
    
    var body: some View {
        ShelfLegacyTile(kind: tileKind, width: tileWidth) {
            ShelfLegacyCoverView(bookId: book.id, coverURL: book.coverURL, fallbackTitle: book.title)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }
                .overlay(
                    ZStack {
                        if isEditing {
                            // Edit Mode: Top-Left Selection Checkmark
                            VStack {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(isSelected ? .blue : .white)
                                        .shadow(color: Color.black.opacity(0.3), radius: 2)
                                        .frame(width: ShelfLegacyMetrics.selectionWidth, height: ShelfLegacyMetrics.selectionHeight)
                                        .padding(.leading, 4)
                                        .padding(.top, 4)
                                        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                                        .accessibilityHint("Taps to toggle selection")
                                    Spacer()
                                }
                                Spacer()
                            }
                        } else {
                            // Normal Mode: Overlays
                            
                            // Top-Right Progress Badge
                            VStack {
                                HStack {
                                    Spacer()
                                    Text(ShelfLegacyPresentation.progressLabel(book.progress))
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(Color.black.opacity(0.9))
                                        .frame(width: ShelfLegacyMetrics.progressWidth, height: ShelfLegacyMetrics.progressHeight)
                                        .background(Color(red: 0.9, green: 0.9, blue: 0.9).opacity(0.4))
                                        .cornerRadius(8)
                                        .padding(.trailing, 4)
                                        .padding(.top, 4)
                                }
                                Spacer()
                            }
                            
                            // Left-Bottom Status Icon
                            VStack {
                                Spacer()
                                HStack {
                                    Image(ShelfLegacyPresentation.statusAssetName(book.status))
                                        .resizable()
                                        .renderingMode(.original)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: ShelfLegacyMetrics.statusWidth, height: ShelfLegacyMetrics.statusHeight)
                                        .padding(.leading, 12)
                                        .padding(.bottom, 4)
                                        .accessibilityLabel("Book Status: \(book.status.rawValue)")
                                    Spacer()
                                }
                            }
                            
                            // Right-Bottom Options Menu
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Menu {
                                        Button(action: onDetails) {
                                            Label("Details", systemImage: "info.circle")
                                        }
                                        
                                        Button(action: onRefresh) {
                                            Label("Refresh", systemImage: "arrow.clockwise")
                                        }
                                        
                                        if let onDelete = onDelete {
                                            Button(role: .destructive, action: onDelete) {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        
                                        if onGoodreads != nil || onDouban != nil || onHistory != nil {
                                            Divider()
                                        }
                                        
                                        if let onGoodreads = onGoodreads {
                                            Button(action: onGoodreads) {
                                                Label("Goodreads", systemImage: "globe")
                                            }
                                        }
                                        
                                        if let onDouban = onDouban {
                                            Button(action: onDouban) {
                                                Label("Douban", systemImage: "globe")
                                            }
                                        }
                                        
                                        if let onHistory = onHistory {
                                            Button(action: onHistory) {
                                                Label("Progress History", systemImage: "chart.bar.xaxis")
                                            }
                                        }
                                    } label: {
                                        Image("options")
                                            .resizable()
                                            .renderingMode(.original)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 64, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .padding(.trailing, -16) // overlaps right edge by 16pt (from constraints)
                                    .padding(.bottom, 4)
                                    .accessibilityLabel("Options")
                                    .accessibilityHint("Shows actions menu")
                                }
                            }
                        }
                    }
                    .frame(width: ShelfLegacyMetrics.coverWidth, height: ShelfLegacyMetrics.coverHeight)
                )
        }
        .contextMenu {
            if !isEditing {
                Button(action: onDetails) {
                    Label("Details", systemImage: "info.circle")
                }
                
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                if let onDelete = onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
                if onGoodreads != nil || onDouban != nil || onHistory != nil {
                    Divider()
                }
                
                if let onGoodreads = onGoodreads {
                    Button(action: onGoodreads) {
                        Label("Goodreads", systemImage: "globe")
                    }
                }
                
                if let onDouban = onDouban {
                    Button(action: onDouban) {
                        Label("Douban", systemImage: "globe")
                    }
                }
                
                if let onHistory = onHistory {
                    Button(action: onHistory) {
                        Label("Progress History", systemImage: "chart.bar.xaxis")
                    }
                }
            }
        }
    }
}
