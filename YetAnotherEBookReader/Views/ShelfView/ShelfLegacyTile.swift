//
//  ShelfLegacyTile.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-27.
//

import SwiftUI

public struct ShelfLegacyTile<Content: View>: View {
    public let kind: ShelfTileKind
    public let width: CGFloat
    public let content: Content?
    
    public init(kind: ShelfTileKind, width: CGFloat, @ViewBuilder content: () -> Content?) {
        self.kind = kind
        self.width = width
        self.content = content()
    }
    
    public init(kind: ShelfTileKind, width: CGFloat) where Content == EmptyView {
        self.kind = kind
        self.width = width
        self.content = nil
    }
    
    public var body: some View {
        ZStack {
            // Background wood asset stretched to fit the tile
            Image(kind.assetName)
                .resizable()
                .renderingMode(.original)
            
            // Fixed cover area centered in the tile
            if let content = content {
                content
                    .frame(width: ShelfLegacyMetrics.coverWidth, height: ShelfLegacyMetrics.coverHeight)
            }
        }
        .frame(width: width, height: ShelfLegacyMetrics.tileHeight)
    }
}

public struct ShelfLegacyFillerTile: View {
    public let kind: ShelfTileKind
    public let width: CGFloat
    
    public init(kind: ShelfTileKind, width: CGFloat) {
        self.kind = kind
        self.width = width
    }
    
    public var body: some View {
        ShelfLegacyTile<EmptyView>(kind: kind, width: width)
            .accessibilityHidden(true)
    }
}

struct ShelfLegacyTile_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ShelfLegacyTile(kind: .left, width: 187) {
                    Color.red
                }
                ShelfLegacyTile(kind: .center, width: 187) {
                    Color.green
                }
                ShelfLegacyTile(kind: .right, width: 187) {
                    Color.blue
                }
            }
            HStack(spacing: 0) {
                ShelfLegacyFillerTile(kind: .left, width: 187)
                ShelfLegacyFillerTile(kind: .center, width: 187)
                ShelfLegacyFillerTile(kind: .right, width: 187)
            }
        }
        .frame(width: 561, height: 400)
        .previewLayout(.sizeThatFits)
    }
}
