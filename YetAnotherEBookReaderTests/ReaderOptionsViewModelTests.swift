//
//  ReaderOptionsViewModelTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026/6/13.
//

import XCTest
import SwiftUI
import Combine
@testable import YetAnotherEBookReader

class ReaderOptionsViewModelTests: XCTestCase {
    var viewModel: ReaderOptionsViewModel!
    var mockModelData: ModelData!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
        viewModel = ReaderOptionsViewModel(modelData: mockModelData, fontsManager: mockModelData.fontsManager)
        cancellables = []
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockModelData = nil
        cancellables = nil
    }
    
    func testInitialization() throws {
        XCTAssertFalse(viewModel.optionsHelpFormat)
        XCTAssertFalse(viewModel.optionsHelpReader)
        XCTAssertFalse(viewModel.optionsHelpFont)
        XCTAssertFalse(viewModel.fontsFolderPresenting)
        XCTAssertFalse(viewModel.fontsDetailPresenting)
    }
    
    func testPopoverToggles() throws {
        viewModel.startImport()
        XCTAssertTrue(viewModel.fontsFolderPresenting)
        
        viewModel.startViewDetails()
        XCTAssertTrue(viewModel.fontsDetailPresenting)
    }
    
    func testDismissAllBindings() throws {
        viewModel.optionsHelpFormat = true
        viewModel.fontsDetailPresenting = true
        
        let expectation = XCTestExpectation(description: "Wait for dismiss publisher")
        
        // Trigger dismiss
        mockModelData.dismissAllSubject.send("")
        
        DispatchQueue.main.async {
            XCTAssertFalse(self.viewModel.optionsHelpFormat)
            XCTAssertFalse(self.viewModel.fontsDetailPresenting)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testPreferredFormatBinding() throws {
        let binding = viewModel.preferredFormatBinding
        binding.wrappedValue = .EPUB
        XCTAssertEqual(binding.wrappedValue, .EPUB)
        XCTAssertEqual(mockModelData.sessionManager.getPreferredFormat(), .EPUB)
    }
}
