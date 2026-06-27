//
//  ReadingPositionSelectionTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-27.
//

import XCTest
@testable import YetAnotherEBookReader

final class ReadingPositionSelectionTests: XCTestCase {
    
    func testSelectFromEmptyArrayReturnsNil() {
        let positions: [BookDeviceReadingPosition] = []
        XCTAssertNil(ReadingPositionSelectionPolicy.latest.select(from: positions))
        XCTAssertNil(ReadingPositionSelectionPolicy.latestForDevice("iPad").select(from: positions))
    }
    
    func testSelectLatestReturnsGlobalMaxEpoch() {
        let p1 = BookDeviceReadingPosition(id: "iPhone", readerName: "Readium", epoch: 1000.0)
        let p2 = BookDeviceReadingPosition(id: "iPad", readerName: "Readium", epoch: 2000.0)
        let p3 = BookDeviceReadingPosition(id: "Mac", readerName: "FolioReader", epoch: 1500.0)
        
        let positions = [p1, p2, p3]
        
        let selected = ReadingPositionSelectionPolicy.latest.select(from: positions)
        XCTAssertEqual(selected?.id, "iPad")
        XCTAssertEqual(selected?.epoch, 2000.0)
    }
    
    func testSelectLatestForDeviceReturnsMaxEpochForThatDevice() {
        let p1 = BookDeviceReadingPosition(id: "iPhone", readerName: "Readium", epoch: 1000.0)
        let p2 = BookDeviceReadingPosition(id: "iPad", readerName: "Readium", epoch: 1500.0)
        let p3 = BookDeviceReadingPosition(id: "iPhone", readerName: "FolioReader", epoch: 2000.0)
        let p4 = BookDeviceReadingPosition(id: "iPad", readerName: "FolioReader", epoch: 1200.0)
        
        let positions = [p1, p2, p3, p4]
        
        let selectedIPhone = ReadingPositionSelectionPolicy.latestForDevice("iPhone").select(from: positions)
        XCTAssertEqual(selectedIPhone?.id, "iPhone")
        XCTAssertEqual(selectedIPhone?.epoch, 2000.0)
        
        let selectedIPad = ReadingPositionSelectionPolicy.latestForDevice("iPad").select(from: positions)
        XCTAssertEqual(selectedIPad?.id, "iPad")
        XCTAssertEqual(selectedIPad?.epoch, 1500.0)
    }
    
    func testSelectLatestForNonExistentDeviceReturnsNil() {
        let p1 = BookDeviceReadingPosition(id: "iPhone", readerName: "Readium", epoch: 1000.0)
        let positions = [p1]
        
        let selected = ReadingPositionSelectionPolicy.latestForDevice("iPad").select(from: positions)
        XCTAssertNil(selected)
    }
    
    func testSelectStableChoiceWhenEpochsAreIdentical() {
        // Input has three positions with identical epochs. The selector should stably
        // choose the one appearing first in the input array.
        let p1 = BookDeviceReadingPosition(id: "iPad", readerName: "Readium", lastReadPage: 10, epoch: 1000.0)
        let p2 = BookDeviceReadingPosition(id: "iPad", readerName: "FolioReader", lastReadPage: 20, epoch: 1000.0)
        let p3 = BookDeviceReadingPosition(id: "iPad", readerName: "YabrPDF", lastReadPage: 30, epoch: 1000.0)
        
        let positions = [p1, p2, p3]
        
        let selected = ReadingPositionSelectionPolicy.latestForDevice("iPad").select(from: positions)
        // First occurrence has lastReadPage = 10
        XCTAssertEqual(selected?.lastReadPage, 10)
        
        // Reordering the input array should yield the new first item
        let reorderedPositions = [p3, p1, p2]
        let selectedReordered = ReadingPositionSelectionPolicy.latestForDevice("iPad").select(from: reorderedPositions)
        XCTAssertEqual(selectedReordered?.lastReadPage, 30)
    }
    
    func testSelectPermutedInputsYieldConsistentWinner() {
        let p1 = BookDeviceReadingPosition(id: "DeviceA", readerName: "A", epoch: 10.0)
        let p2 = BookDeviceReadingPosition(id: "DeviceA", readerName: "B", epoch: 30.0)
        let p3 = BookDeviceReadingPosition(id: "DeviceA", readerName: "C", epoch: 20.0)
        
        // In all permutations of [p1, p2, p3], p2 (epoch 30.0) must win
        let permutations = [
            [p1, p2, p3],
            [p1, p3, p2],
            [p2, p1, p3],
            [p2, p3, p1],
            [p3, p1, p2],
            [p3, p2, p1]
        ]
        
        for input in permutations {
            let selected = ReadingPositionSelectionPolicy.latest.select(from: input)
            XCTAssertEqual(selected?.readerName, "B")
            XCTAssertEqual(selected?.epoch, 30.0)
        }
    }
}
