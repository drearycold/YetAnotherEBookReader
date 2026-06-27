//
//  ShelfLegacyStyleTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-27.
//

import XCTest
@testable import YetAnotherEBookReader

class ShelfLegacyStyleTests: XCTestCase {
    
    func testColumnCountBoundary() {
        // baseTileWidth is 150
        // columnCount = max(1, Int(floor(containerWidth / 150)))
        XCTAssertEqual(ShelfLegacyLayout.columnCount(containerWidth: 149), 1)
        XCTAssertEqual(ShelfLegacyLayout.columnCount(containerWidth: 150), 1)
        XCTAssertEqual(ShelfLegacyLayout.columnCount(containerWidth: 299), 1)
        XCTAssertEqual(ShelfLegacyLayout.columnCount(containerWidth: 300), 2)
        XCTAssertEqual(ShelfLegacyLayout.columnCount(containerWidth: 393), 2)
        XCTAssertEqual(ShelfLegacyLayout.columnCount(containerWidth: 414), 2)
        XCTAssertEqual(ShelfLegacyLayout.columnCount(containerWidth: 744), 4)
    }
    
    func testTileWidthCalculation() {
        // tileWidth = containerWidth / columnCount
        XCTAssertEqual(ShelfLegacyLayout.tileWidth(containerWidth: 300), 150.0)
        XCTAssertEqual(ShelfLegacyLayout.tileWidth(containerWidth: 400), 200.0) // 400 / 2 = 200
        XCTAssertEqual(ShelfLegacyLayout.tileWidth(containerWidth: 744), 186.0) // 744 / 4 = 186
    }
    
    func testTileKindDistribution() {
        // Single column layout should use .left
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 0, columnCount: 1), .left)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 1, columnCount: 1), .left)
        
        // 2 column layout:
        // index 0 -> left, index 1 -> right, index 2 -> left, index 3 -> right
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 0, columnCount: 2), .left)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 1, columnCount: 2), .right)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 2, columnCount: 2), .left)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 3, columnCount: 2), .right)
        
        // 4 column layout:
        // index 0 -> left, index 1 -> center, index 2 -> center, index 3 -> right
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 0, columnCount: 4), .left)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 1, columnCount: 4), .center)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 2, columnCount: 4), .center)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 3, columnCount: 4), .right)
        XCTAssertEqual(ShelfLegacyLayout.tileKind(index: 4, columnCount: 4), .left)
    }
    
    func testCompletedTileCount() {
        // completedTileCount = ceil(itemCount / columnCount) * columnCount
        
        // 2 columns
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 0, columnCount: 2), 0)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 1, columnCount: 2), 2)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 3, columnCount: 2), 4)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 4, columnCount: 2), 4)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 5, columnCount: 2), 6)
        
        // 4 columns
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 0, columnCount: 4), 0)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 1, columnCount: 4), 4)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 3, columnCount: 4), 4)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 4, columnCount: 4), 4)
        XCTAssertEqual(ShelfLegacyLayout.completedTileCount(itemCount: 5, columnCount: 4), 8)
    }
    
    func testViewportTileCount() {
        // tileHeight is 200
        // contentRows = ceil(itemCount / columnCount)
        // viewportRows = ceil(viewportHeight / 200)
        // finalRows = max(contentRows, viewportRows)
        // returns finalRows * columnCount
        
        // columnCount = 2, contentCount = 0
        // viewportHeight = 100 (less than 1 row) -> viewportRows = 1
        XCTAssertEqual(ShelfLegacyLayout.viewportTileCount(itemCount: 0, columnCount: 2, viewportHeight: 100.0), 2)
        
        // viewportHeight = 200 (exactly 1 row) -> viewportRows = 1
        XCTAssertEqual(ShelfLegacyLayout.viewportTileCount(itemCount: 0, columnCount: 2, viewportHeight: 200.0), 2)
        
        // viewportHeight = 300 (1.5 rows) -> viewportRows = 2
        XCTAssertEqual(ShelfLegacyLayout.viewportTileCount(itemCount: 0, columnCount: 2, viewportHeight: 300.0), 4)
        
        // viewportHeight = 400 (exactly 2 rows) -> viewportRows = 2
        XCTAssertEqual(ShelfLegacyLayout.viewportTileCount(itemCount: 0, columnCount: 2, viewportHeight: 400.0), 4)
        
        // Content rows exceed viewport rows:
        // columnCount = 2, itemCount = 5 -> contentRows = 3. viewportHeight = 300 -> viewportRows = 2
        // max(3, 2) = 3 rows -> 6 tiles
        XCTAssertEqual(ShelfLegacyLayout.viewportTileCount(itemCount: 5, columnCount: 2, viewportHeight: 300.0), 6)
        
        // Viewport rows exceed content rows:
        // columnCount = 2, itemCount = 1 -> contentRows = 1. viewportHeight = 600 -> viewportRows = 3
        // max(1, 3) = 3 rows -> 6 tiles
        XCTAssertEqual(ShelfLegacyLayout.viewportTileCount(itemCount: 1, columnCount: 2, viewportHeight: 600.0), 6)
    }
    
    func testProgressLabel() {
        XCTAssertEqual(ShelfLegacyPresentation.progressLabel(-1), "0%")
        XCTAssertEqual(ShelfLegacyPresentation.progressLabel(0), "0%")
        XCTAssertEqual(ShelfLegacyPresentation.progressLabel(61), "61%")
        XCTAssertEqual(ShelfLegacyPresentation.progressLabel(100), "FIN")
        XCTAssertEqual(ShelfLegacyPresentation.progressLabel(101), "FIN")
    }
    
    func testStatusAssetName() {
        XCTAssertEqual(ShelfLegacyPresentation.statusAssetName(.ready), "icon-book-ready")
        XCTAssertEqual(ShelfLegacyPresentation.statusAssetName(.noConnect), "icon-book-noconnect")
        XCTAssertEqual(ShelfLegacyPresentation.statusAssetName(.hasUpdate), "icon-book-hasupdate")
        XCTAssertEqual(ShelfLegacyPresentation.statusAssetName(.downloading), "icon-book-downloading")
        XCTAssertEqual(ShelfLegacyPresentation.statusAssetName(.local), "icon-book-local")
        XCTAssertEqual(ShelfLegacyPresentation.statusAssetName(.updating), "icon-book-updating")
    }
}
