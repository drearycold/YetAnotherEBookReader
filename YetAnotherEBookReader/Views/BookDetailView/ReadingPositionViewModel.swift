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
    
    let percentFormatter = NumberFormatter()
    let dateFormatter = DateFormatter()
    
    var modified = false
    
    init(modelData: ModelData, book: CalibreBook, positions: [BookDeviceReadingPosition]) {
        self.modelData = modelData
        self.book = book
        self.positions = book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
        
        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = .current
    }
    
    func positionsByLatestStyle() -> [BookDeviceReadingPosition] {
        guard let latest = positions.first else { return [] }
        
        return positions.filter { $0.structuralStyle == latest.structuralStyle && $0.positionTrackingStyle == latest.positionTrackingStyle }
    }
    
    func positionsByLatestStyle(deviceId: String) -> [BookDeviceReadingPosition] {
        let devicePositions = positions.filter({ $0.id == deviceId })
        guard let latest = devicePositions.first else { return [] }
        
        return devicePositions.filter { $0.structuralStyle == latest.structuralStyle && $0.positionTrackingStyle == latest.positionTrackingStyle }
    }
    
    func positionsDeviceKeys() -> [String] {
        return positions.reduce(into: [String: Double]()) { partialResult, position in
            if (partialResult[position.id] ?? -1.0) < position.epoch {
                partialResult[position.id] = position.epoch
            }
        }.sorted(by: { $0.value > $1.value }).map { $0.key }
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
    
    let percentFormatter = NumberFormatter()
    let dateFormatter = DateFormatter()
    
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
        
        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = .current
    }
}

