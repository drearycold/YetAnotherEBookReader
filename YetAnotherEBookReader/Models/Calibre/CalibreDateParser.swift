//
//  CalibreDateParser.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/7/4.
//

import Foundation

func parseLastModified(_ lastModified: String) -> Date? {
    let parserOne = ISO8601DateFormatter()
    parserOne.formatOptions = .withInternetDateTime
    let parserTwo = ISO8601DateFormatter()
    parserTwo.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    return parserTwo.date(from: lastModified) ?? parserOne.date(from: lastModified)
}
