import XCTest
import SwiftUI
@testable import YetAnotherEBookReader

class BookDetailViewModelTests: XCTestCase {
    
    var viewModel: BookDetailViewModel!
    var mockModelData: ModelData!
    var mockBookRealm: CalibreBookRealm!
    var mockCalibreBook: CalibreBook!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
        viewModel = BookDetailViewModel(modelData: mockModelData)
        
        mockBookRealm = CalibreBookRealm()
        mockBookRealm.serverUUID = "mock-uuid"
        mockBookRealm.libraryName = "Mock Library"
        mockBookRealm.idInLib = 123
        mockBookRealm.title = "Test Book"
        
        let library = CalibreLibrary(server: CalibreServer(uuid: UUID(), name: "MockServer", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "lib1", name: "Mock Library")
        mockCalibreBook = CalibreBook(id: 123, library: library)
        mockCalibreBook.title = "Test Book"
        
        viewModel.setup(book: mockBookRealm, calibreBook: mockCalibreBook)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        mockModelData = nil
        mockBookRealm = nil
        mockCalibreBook = nil
    }

    func testViewModelSetup() throws {
        XCTAssertNotNil(viewModel.listVM)
        XCTAssertEqual(viewModel.listVM?.book.id, 123)
        XCTAssertEqual(viewModel.listVM?.book.title, "Test Book")
    }
    
    func testReadBookWhenNotInShelf() throws {
        mockCalibreBook.inShelf = false
        viewModel.readBook(book: mockCalibreBook)
        XCTAssertNotNil(viewModel.alertItem, "Alert item should be set if there is no format to download")
    }
    
    func testReadBookWhenInShelf() throws {
        mockCalibreBook.inShelf = true
        viewModel.readBook(book: mockCalibreBook)
        XCTAssertNotNil(mockModelData.readerInfo, "Reader info should be populated when reading an in-shelf book")
    }
    
    func testParseManifestToTOCSuccess() throws {
        let jsonString = "{\"toc\": {\"children\": [{\"title\": \"Chapter 1\"}, {\"title\": \"Chapter 2\"}]}}"
        let data = jsonString.data(using: .utf8)!
        viewModel.parseManifestToTOC(json: data)
        XCTAssertEqual(viewModel.previewViewModel.toc, "Chapter 1\nChapter 2\n", "TOC should be correctly parsed from manifest JSON")
    }
    
    func testParseManifestToTOCWaiting() throws {
        let jsonString = "{\"job_status\": \"waiting\"}"
        let data = jsonString.data(using: .utf8)!
        viewModel.parseManifestToTOC(json: data)
        XCTAssertEqual(viewModel.previewViewModel.toc, "Generating TOC, Please try again later", "Should show generating message when job is waiting")
    }
    
    func testParseManifestToTOCInvalidJSON() throws {
        let data = "Invalid JSON".data(using: .utf8)!
        viewModel.parseManifestToTOC(json: data)
        #if DEBUG
        XCTAssertEqual(viewModel.previewViewModel.toc, "Invalid JSON", "Should fallback to raw string for invalid JSON in DEBUG")
        #else
        XCTAssertEqual(viewModel.previewViewModel.toc, "Without TOC", "Should fallback to Without TOC for invalid JSON")
        #endif
    }

    func testUpdatingMetadata() throws {
        XCTAssertFalse(viewModel.updatingMetadata)
        mockModelData.updatingMetadata = true
        XCTAssertTrue(viewModel.updatingMetadata)
    }

    func testPushAndPopPresenting() throws {
        var presenting = false
        let binding = Binding<Bool>(
            get: { presenting },
            set: { presenting = $0 }
        )
        
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        viewModel.pushPresenting(binding)
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        
        viewModel.popPresenting()
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
    }

    func testConvertBookRealm() throws {
        let result = viewModel.convert(bookRealm: mockBookRealm)
        XCTAssertNil(result, "Should return nil if library is not queryable in mock model data")
    }

    func testPresentationSheetProperties() throws {
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.presentingReadingSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.presentingReadingSheet = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.presentingPreviewSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.presentingPreviewSheet = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.activityListViewPresenting = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.activityListViewPresenting = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.readingPositionHistoryViewPresenting = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        viewModel.readingPositionHistoryViewPresenting = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
    }

    func testPresentationSheetPropertiesBindingInteractions() throws {
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        
        viewModel.presentingReadingSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        
        let binding = mockModelData.presentingStack.last
        XCTAssertNotNil(binding)
        XCTAssertTrue(binding?.wrappedValue ?? false)
        
        // Dismiss via binding (e.g. SwiftUI sheet dismissal)
        binding?.wrappedValue = false
        XCTAssertFalse(viewModel.presentingReadingSheet)
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
    }
}

class ReadingPositionViewModelTests: XCTestCase {
    var mockModelData: ModelData!
    var listViewModel: ReadingPositionListViewModel!
    var mockBook: CalibreBook!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
        
        let library = CalibreLibrary(server: CalibreServer(uuid: UUID(), name: "MockServer", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "lib1", name: "Mock Library")
        mockBook = CalibreBook(id: 123, library: library)
        mockBook.title = "Test Book"
        
        listViewModel = ReadingPositionListViewModel(modelData: mockModelData, book: mockBook, positions: [])
    }
    
    override func tearDownWithError() throws {
        listViewModel = nil
        mockBook = nil
        mockModelData = nil
    }
    
    func testDetailViewModelInitialization() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        let detailVM = ReadingPositionDetailViewModel(modelData: mockModelData, listModel: listViewModel, position: position)
        
        XCTAssertEqual(detailVM.position.id, "device-1")
        XCTAssertEqual(detailVM.selectedFormatReader, .YabrEPUB)
        XCTAssertEqual(detailVM.selectedFormat, .EPUB)
    }
    
    func testDetailViewModelPresentingSheet() throws {
        let position = BookDeviceReadingPosition(id: "device-1", readerName: ReaderType.YabrEPUB.rawValue)
        let detailVM = ReadingPositionDetailViewModel(modelData: mockModelData, listModel: listViewModel, position: position)
        
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
        detailVM.presentingReadSheet = true
        XCTAssertEqual(mockModelData.presentingStack.count, 1)
        detailVM.presentingReadSheet = false
        XCTAssertEqual(mockModelData.presentingStack.count, 0)
    }
    
    func testHistoryViewModelLoadData() throws {
        let historyVM = ReadingPositionHistoryViewModel(modelData: mockModelData, library: mockBook.library, bookId: mockBook.id)
        XCTAssertEqual(historyVM.maxMinutes, 0)
        
        historyVM.loadData()
        
        XCTAssertNotNil(historyVM.readingStatistics)
    }
}

class ActivityListViewModelTests: XCTestCase {
    var mockModelData: ModelData!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
    }
    
    override func tearDownWithError() throws {
        mockModelData = nil
    }
    
    func testInitialization() throws {
        let viewModel = ActivityListViewModel(modelData: mockModelData)
        XCTAssertEqual(viewModel.activities.count, 0)
    }
}