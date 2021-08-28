//
//  ReadingPositionViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/25.
//

import Foundation

class ReadingPositionListViewModel: ObservableObject {
    var modelData: ModelData
    @Published var book: CalibreBook
    
    var modified = false
    
    init(modelData: ModelData, book: CalibreBook) {
        self.modelData = modelData
        self.book = book
    }
    
    func removePosition(_ deviceName: String) {
        book.readPos.removePosition(deviceName)
        modified = true
    }
}

class ReadingPositionDetailViewModel: ObservableObject {
    var modelData: ModelData
    @Published var book: CalibreBook
    @Published var position: BookDeviceReadingPosition
    
    @Published var selectedFormat = Format.UNKNOWN
    @Published var selectedFormatReader = ReaderType.UNSUPPORTED
    @Published var startPage = ""
    
    init (modelData: ModelData, book: CalibreBook, position: BookDeviceReadingPosition) {
        self.modelData = modelData
        self.book = book
        self.position = position
        
        if let format = modelData.formatOfReader(readerName: position.readerName) {
            self.selectedFormat = format
        }
        if let reader = ReaderType(rawValue: position.readerName) {
            self.selectedFormatReader = reader
        }
        
        startPage = position.lastReadPage.description
    }
}

