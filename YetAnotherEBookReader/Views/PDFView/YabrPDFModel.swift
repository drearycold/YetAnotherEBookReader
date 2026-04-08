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
