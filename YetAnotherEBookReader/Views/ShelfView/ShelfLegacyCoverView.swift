//
//  ShelfLegacyCoverView.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-27.
//

import SwiftUI
import KingfisherSwiftUI

public enum ShelfCoverLoadState {
    case loading
    case success
    case failure
}

public struct ShelfLegacyCoverView: View {
    public let bookId: String
    public let coverURL: String
    public let fallbackTitle: String
    
    @State private var loadState: ShelfCoverLoadState = .loading
    
    public init(bookId: String, coverURL: String, fallbackTitle: String) {
        self.bookId = bookId
        self.coverURL = coverURL
        self.fallbackTitle = fallbackTitle
    }
    
    public var body: some View {
        ZStack {
            if let url = URL(string: coverURL), !coverURL.isEmpty {
                KFImage(url)
                    .onSuccess { _ in
                        loadState = .success
                    }
                    .onFailure { _ in
                        loadState = .failure
                    }
                    .placeholder {
                        ZStack {
                            Color.gray.opacity(0.15)
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: ShelfLegacyMetrics.coverWidth, height: ShelfLegacyMetrics.coverHeight)
                    .clipped()
            } else {
                fallbackView
                    .onAppear { loadState = .failure }
            }
            
            // Overlays
            if loadState == .success {
                // Wooden spine asset overlay (leading edge, 8pt wide, 160pt high)
                HStack {
                    Image("spine")
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: ShelfLegacyMetrics.spineWidth, height: ShelfLegacyMetrics.coverHeight)
                    Spacer()
                }
            } else if loadState == .failure {
                fallbackView
            }
        }
        .frame(width: ShelfLegacyMetrics.coverWidth, height: ShelfLegacyMetrics.coverHeight)
        .shadow(color: Color.black.opacity(0.7), radius: 10, x: 0, y: 0)
        .onChange(of: bookId) { _ in
            loadState = .loading
        }
        .onChange(of: coverURL) { _ in
            loadState = .loading
        }
    }
    
    private var fallbackView: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Text(fallbackTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(8)
                .lineLimit(6)
                .frame(width: ShelfLegacyMetrics.coverWidth, height: ShelfLegacyMetrics.coverHeight)
        }
    }
}
