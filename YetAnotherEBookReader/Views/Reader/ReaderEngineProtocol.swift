//
//  ReaderEngineProtocol.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-15.
//

import Foundation
import UIKit

struct ReaderEnginePosition {
    var pageNumber: Int = 1
    var maxPage: Int = 1
    var pageOffsetX: Int = 0
    var pageOffsetY: Int = 0
    var bookProgress: Double = 0.0      // 0 - 100
    var chapterProgress: Double = 0.0   // 0 - 100
    var chapterName: String? = nil
    var cfi: String? = nil
    
    // For non-linear book structures (e.g. PDF/FolioReader custom tracking)
    var structuralStyle: Int = 0
    var structuralRootPageNumber: Int = 0
    var positionTrackingStyle: Int = 0
}

protocol ReaderEngineDelegate: AnyObject {
    func readerEngine(_ engine: AnyObject, didUpdatePosition position: ReaderEnginePosition)
}
