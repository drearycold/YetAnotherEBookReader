//
//  SupportInfoViewModelTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by opencode on 2026/6/18.
//

import XCTest
import SwiftUI
import Combine
@testable import YetAnotherEBookReader

class SupportInfoViewModelTests: XCTestCase {
    var viewModel: SupportInfoViewModel!
    
    override func setUpWithError() throws {
        viewModel = SupportInfoViewModel()
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
    }
    
    func testInitialization() throws {
        XCTAssertFalse(viewModel.isExporting)
        XCTAssertFalse(viewModel.showFolderPicker)
        XCTAssertEqual(viewModel.exportProgress, 0)
        XCTAssertEqual(viewModel.currentExportFile, "")
        XCTAssertEqual(viewModel.alertMessage, "")
        XCTAssertFalse(viewModel.showAlert)
    }
    
    func testOnAppear() throws {
        viewModel.onAppear()
        XCTAssertEqual(viewModel.yabrPrivacyHtml, YabrAppInfo.shared.privacyHtml)
        XCTAssertEqual(viewModel.yabrTermsHtml, YabrAppInfo.shared.termsHtml)
        XCTAssertEqual(viewModel.yabrVersionHtml, YabrAppInfo.shared.versionHtml)
    }
}
