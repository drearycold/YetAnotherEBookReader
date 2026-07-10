//
//  ShelfLegacyStyle.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-27.
//

import SwiftUI

public enum ShelfTileKind: String, Equatable {
    case left
    case center
    case right
    
    public var assetName: String {
        return rawValue
    }
}

public struct ShelfLegacyMetrics {
    public static let baseTileWidth: CGFloat = 150.0
    public static let tileHeight: CGFloat = 200.0
    public static let coverWidth: CGFloat = 120.0
    public static let coverHeight: CGFloat = 160.0
    public static let sectionHeaderHeight: CGFloat = 32.0
    public static let spineWidth: CGFloat = 8.0
    
    public static let progressWidth: CGFloat = 36.0
    public static let progressHeight: CGFloat = 24.0
    
    public static let statusWidth: CGFloat = 20.0
    public static let statusHeight: CGFloat = 24.0
    
    public static let selectionWidth: CGFloat = 32.0
    public static let selectionHeight: CGFloat = 32.0

    public static let shelfAdInlineMaxHeight: CGFloat = 60.0
    public static let shelfAdInlineRowHeight: CGFloat = 104.0
    public static let shelfNativeStripRowHeight: CGFloat = 200.0
    public static let shelfSectionRowHeight: CGFloat = sectionHeaderHeight + tileHeight
    public static let shelfTabBarExclusionHeight: CGFloat = 112.0
    
    public static let shelfBackgroundColor = Color(red: 0xC4 / 255.0, green: 0x9E / 255.0, blue: 0x7A / 255.0)
}

public struct ShelfLegacyLayout {
    public static func columnCount(containerWidth: CGFloat) -> Int {
        return max(1, Int(floor(containerWidth / ShelfLegacyMetrics.baseTileWidth)))
    }
    
    public static func tileWidth(containerWidth: CGFloat) -> CGFloat {
        let cols = CGFloat(columnCount(containerWidth: containerWidth))
        return containerWidth / cols
    }
    
    public static func tileKind(index: Int, columnCount: Int) -> ShelfTileKind {
        if columnCount <= 1 {
            return .left
        }
        let colIndex = index % columnCount
        if colIndex == 0 {
            return .left
        } else if colIndex == columnCount - 1 {
            return .right
        } else {
            return .center
        }
    }
    
    public static func completedTileCount(itemCount: Int, columnCount: Int) -> Int {
        guard columnCount > 0 else { return 0 }
        let contentRows = Int(ceil(Double(itemCount) / Double(columnCount)))
        return contentRows * columnCount
    }
    
    public static func viewportTileCount(itemCount: Int, columnCount: Int, viewportHeight: CGFloat) -> Int {
        guard columnCount > 0 else { return 0 }
        let contentRows = Int(ceil(Double(itemCount) / Double(columnCount)))
        var viewportRows = Int(ceil(viewportHeight / ShelfLegacyMetrics.tileHeight))
        if viewportRows < 1 {
            viewportRows = 1
        }
        let finalRows = max(contentRows, viewportRows)
        return finalRows * columnCount
    }
}

public struct ShelfLegacyPresentation {
    public static func progressLabel(_ progress: Int) -> String {
        if progress <= 0 {
            return "0%"
        } else if progress >= 100 {
            return "FIN"
        } else {
            return "\(progress)%"
        }
    }
    
    public static func statusAssetName(_ status: ShelfBookStatus) -> String {
        switch status {
        case .ready:
            return "icon-book-ready"
        case .noConnect:
            return "icon-book-noconnect"
        case .hasUpdate:
            return "icon-book-hasupdate"
        case .downloading:
            return "icon-book-downloading"
        case .local:
            return "icon-book-local"
        case .updating:
            return "icon-book-updating"
        }
    }
}
