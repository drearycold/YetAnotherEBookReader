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
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDetails: () -> Void
    let onRefresh: () -> Void
    var onDelete: (() -> Void)? = nil
    var onGoodreads: (() -> Void)? = nil
    var onDouban: (() -> Void)? = nil
    var onHistory: (() -> Void)? = nil
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    if let url = URL(string: book.coverURL) {
                        KFImage(url)
                            .placeholder {
                                ZStack {
                                    Color.gray.opacity(0.15)
                                    Image(systemName: "book.closed")
                                        .font(.title)
                                        .foregroundColor(.gray)
                                }
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 110, height: 160)
                            .clipped()
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                    } else {
                        ZStack {
                            Color.gray.opacity(0.15)
                            Image(systemName: "book.closed")
                                .font(.title)
                                .foregroundColor(.gray)
                        }
                        .frame(width: 110, height: 160)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                    }
                    
                    // Status badge overlay
                    if !isEditing {
                        VStack {
                            HStack {
                                Spacer()
                                switch book.status {
                                case .noConnect:
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 10))
                                        .padding(5)
                                        .background(Circle().fill(Color.orange))
                                        .padding(6)
                                case .downloading:
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                        .padding(5)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                        .padding(6)
                                case .hasUpdate:
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 10, height: 10)
                                        .padding(8)
                                case .local:
                                    Text("Local")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.green))
                                        .padding(6)
                                default:
                                    EmptyView()
                                }
                            }
                            Spacer()
                        }
                        .frame(width: 110, height: 160)
                    }
                    
                    // Selection checkmark
                    if isEditing {
                        Color.black.opacity(isSelected ? 0.3 : 0.05)
                            .cornerRadius(12)
                            .frame(width: 110, height: 160)
                        
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(isSelected ? .blue : .white)
                            .shadow(color: Color.black.opacity(0.3), radius: 2)
                            .padding(8)
                    }
                }
                .frame(width: 110, height: 160)
                
                // Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * CGFloat(min(100, max(0, book.progress))) / 100.0)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(book.progress)%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                
                // Title
                Text(book.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .frame(width: 110)
        }
        .buttonStyle(PlainButtonStyle())
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
