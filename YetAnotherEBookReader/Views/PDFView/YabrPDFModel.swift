//
//  YabrPDFModel.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/4/16.
//

import Foundation
import CoreGraphics
import UIKit

enum PDFAutoScaler: String, CaseIterable, Identifiable {
    case Custom
    case Width
    case Height
    case Page
    
    var id: String { self.rawValue }
}

enum PDFReadDirection: String, CaseIterable, Identifiable {
    case LtR_TtB
    case TtB_RtL
    
    var id: String { self.rawValue }
}

enum PDFScrollDirection: String, CaseIterable, Identifiable {
    case Vertical
    case Horizontal
    
    var id: String { self.rawValue }
}

enum PDFThemeMode: String, CaseIterable, Identifiable {
    case none
    case serpia
    case forest
    case dark
    
    var id: String { self.rawValue }
}

enum PDFLayoutMode: String, CaseIterable, Identifiable {
    case Page
    case Scroll
    
    var id: String { self.rawValue }
}

struct PDFOptions: Equatable {
    var id: Int32 = 0
    var libraryName = ""
    var themeMode = PDFThemeMode.serpia
    var selectedAutoScaler = PDFAutoScaler.Width
    var pageMode = PDFLayoutMode.Page
    var readingDirection = PDFReadDirection.LtR_TtB
    var scrollDirection = PDFScrollDirection.Vertical
    var hMarginAutoScaler = CGFloat(5.0)
    var vMarginAutoScaler = CGFloat(5.0)
    var hMarginDetectStrength = CGFloat(2.0)
    var vMarginDetectStrength = CGFloat(2.0)
    var marginOffset = CGFloat(0.0)
    var lastScale = CGFloat(1.0)
    var rememberInPagePosition = true
    
    var isDark: Bool {
        themeMode == .dark
    }
    
    func isDark<T>(_ f: T, _ l: T) -> T{
        isDark ? f : l
    }
    
    var fillColor: CGColor {
        switch (themeMode) {
        case .none:
            return .init(gray: 0.0, alpha: 0.0)
        case .serpia:   //#FBF0D9
            return CGColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
        case .forest:   //#BAD5C1
            return CGColor(
                red: CGFloat(Int("BA", radix: 16) ?? 255) / 255.0,
                green: CGFloat(Int("D5", radix: 16) ?? 255) / 255.0,
                blue: CGFloat(Int("C1", radix: 16) ?? 255) / 255.0,
                alpha: 1.0)
        case .dark:
            return .init(gray: 0.0, alpha: 1.0)
        }
    }
}

struct PageViewPosition {
    var scaler = CGFloat()
    var point = CGPoint()
    var viewSize = CGSize()
}

struct PageVisibleContentKey: Hashable {
    let pageNumber: Int
    let readingDirection: PDFReadDirection
    let hMarginDetectStrength: Double
    let vMarginDetectStrength: Double
}

struct PageVisibleContentValue {
    let bounds: CGRect
    let thumbImage: UIImage?
    var lastUsed = Date()
}

struct PDFBookmark {
    struct Location: Codable, Comparable {
        var page: Int
        var offset: CGPoint
        
        static func < (lhs: PDFBookmark.Location, rhs: PDFBookmark.Location) -> Bool {
            if lhs.page != rhs.page { return lhs.page < rhs.page }
            return lhs.offset.y < rhs.offset.y
        }
    }
    
    let pos: Location
    
    var title: String
    var date: Date
}

struct PDFHighlight {
    struct PageLocation: Codable {
        var page: Int
        var ranges: [NSRange]
    }
    
    var uuid: UUID
    var pos: [PageLocation]
    
    var type: Int
    var content: String
    var note: String?
    var date: Date

    
}
