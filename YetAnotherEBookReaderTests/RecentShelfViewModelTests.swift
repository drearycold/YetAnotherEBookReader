//
//  RecentShelfViewModelTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by opencode on 2026/6/18.
//

import XCTest
import SwiftUI
import Combine
@testable import YetAnotherEBookReader

@MainActor class RecentShelfViewModelTests: XCTestCase {
    var viewModel: RecentShelfViewModel!
    var mockModelData: ModelData!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
        viewModel = RecentShelfViewModel(modelData: mockModelData)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockModelData = nil
    }
    
    func testInitialization() throws {
        XCTAssertEqual(viewModel.books.count, 0)
    }
}
