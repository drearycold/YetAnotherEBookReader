//
//  BookPreviewViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/29.
//

import Foundation

class BookPreviewViewModel: ObservableObject {
    var modelData: ModelData!
    @Published var book: CalibreBook!
    @Published var url: URL!
    @Published var format = Format.UNKNOWN
    @Published var reader = ReaderType.UNSUPPORTED
    @Published var toc = "Initializing"
    
    init() {
    }
    
    init (modelData: ModelData, book: CalibreBook, url: URL, format: Format, reader: ReaderType) {
        self.modelData = modelData
        self.book = book
        self.url = url
        self.format = format
        self.reader = reader
    }
    
}
