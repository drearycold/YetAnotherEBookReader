//
//  CalibreDateParser.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/7/4.
//

import Foundation

func parseLastModified(_ lastModified: String) -> Date? {
    // ISO8601DateFormatter truncates fractions to milliseconds. Calibre can
    // change metadata more than once within that interval.
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(lastModified) {
        return date
    }
    return ISO8601DateFormatter().date(from: lastModified)
}
