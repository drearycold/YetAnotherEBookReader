//
//  CalibreActivityModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: activity log classes. Lives in Network alongside
//  CalibreActivityLogger.swift.
//

import Foundation

class CalibreActivity {
    let type: String
    
    init(_ type: String) {
        self.type = type
    }
}

class CalibreActivityStart: CalibreActivity {
    let request: URLRequest
    let startDatetime: Date
    let bookId: Int32?
    let libraryId: String?
    
    init(_ type: String, _ request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        self.request = request
        self.startDatetime = startDatetime
        self.bookId = bookId
        self.libraryId = libraryId
        
        super.init(type)
    }
}

class CalibreActivityFinish: CalibreActivity {
    let request: URLRequest
    let startDatetime: Date
    let finishDatetime: Date
    let errMsg: String
    
    init(_ type: String, _ request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        self.request = request
        self.startDatetime = startDatetime
        self.finishDatetime = finishDatetime
        self.errMsg = errMsg
        
        super.init(type)
    }
}
