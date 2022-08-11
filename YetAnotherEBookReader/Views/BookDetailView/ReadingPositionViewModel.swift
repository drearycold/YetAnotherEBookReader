//
//  ReadingPositionViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/25.
//

import Foundation

class ReadingPositionListViewModel: ObservableObject {
    @Published var modelData: ModelData
    @Published var book: CalibreBook
    
    @Published var positions: [BookDeviceReadingPosition]
    
    var modified = false
    
    init(modelData: ModelData, book: CalibreBook, positions: [BookDeviceReadingPosition]) {
        self.modelData = modelData
        self.book = book
        self.positions = book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
    }
    
    func removePosition(_ deviceName: String) {
        book.readPos.removePosition(deviceName)
        modified = true
    }
}

class ReadingPositionDetailViewModel: ObservableObject {
    @Published var modelData: ModelData
    @Published var listModel: ReadingPositionListViewModel
    @Published var position: BookDeviceReadingPosition
    
    @Published var selectedFormat = Format.UNKNOWN
    @Published var selectedFormatReader = ReaderType.UNSUPPORTED
    @Published var startPage = ""
    
    init (modelData: ModelData, listModel: ReadingPositionListViewModel, position: BookDeviceReadingPosition) {
        self.modelData = modelData
        self.listModel = listModel
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

