//
//  YabrPDFModel.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/4/16.
//

import Foundation
import CoreGraphics
import UIKit

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
    /// The region modes are part of the key, so changing one never reuses the
    /// regions found under the other.
    var spreadMode = PDFSpreadMode.Off
    var columnsMode = PDFColumnsMode.Off
}

extension PageVisibleContentKey {
    /// The key for `pageNumber` under `options`.
    init(pageNumber: Int, options: PDFPreferenceValue) {
        self.init(
            pageNumber: pageNumber,
            readingDirection: options.readingDirection,
            hMarginDetectStrength: options.hMarginDetectStrength,
            vMarginDetectStrength: options.vMarginDetectStrength,
            spreadMode: options.spreadMode,
            columnsMode: options.columnsMode
        )
    }
}

struct PageVisibleContentValue {
    let bounds: CGRect
    /// The parts of the page read one after another (#97), in reading order.
    /// Empty when the page reads whole.
    var regions: [PDFReadingRegion] = []
    let thumbImage: UIImage?
    var lastUsed = Date()
}

/// A part of a page read on its own (#97): one half of a two-page spread, one
/// column, or a full-width block between columns. `rect` is in the same space as
/// `PageVisibleContentValue.bounds`: crop-relative page space, top-down.
struct PDFReadingRegion: Equatable {
    enum Kind: Equatable {
        case spreadHalf
        case spanning
        case column
    }

    var rect: CGRect
    var kind: Kind
}

/// What detection found on a page: its content bounds, and the regions it is
/// read in when there are two or more.
struct PDFPageReadingLayout: Equatable {
    var bounds: CGRect
    var regions: [PDFReadingRegion]

    var readsWhole: Bool { regions.count < 2 }
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
