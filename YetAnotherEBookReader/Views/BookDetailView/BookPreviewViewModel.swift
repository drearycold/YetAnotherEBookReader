//
//  BookPreviewViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/29.
//

import Foundation

class BookPreviewViewModel: ObservableObject {
    var container: AppContainer!
    @Published var book: CalibreBook!
    @Published var url: URL!
    @Published var format = Format.UNKNOWN
    @Published var reader = ReaderType.UNSUPPORTED
    @Published var toc = "Initializing"
    
    init() {
    }
    
    init (container: AppContainer, book: CalibreBook, url: URL, format: Format, reader: ReaderType) {
        self.container = container
        self.book = book
        self.url = url
        self.format = format
        self.reader = reader
    }
    
}
