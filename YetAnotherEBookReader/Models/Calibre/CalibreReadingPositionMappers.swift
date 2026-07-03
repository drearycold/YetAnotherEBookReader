//
//  CalibreReadingPositionMappers.swift
//  YetAnotherEBookReader
//

import Foundation

extension BookDeviceReadingPosition {
    public init?(entry: CalibreBookLastReadPositionEntry) {
        guard let vndFirstRange = entry.cfi.range(of: ";vndYabr_") ?? entry.cfi.range(of: ";vnd_"),
              let vndEndRange = entry.cfi.range(of: "]", range: vndFirstRange.upperBound..<entry.cfi.endIndex)
        else { return nil }

        let vndParameters = entry.cfi[vndFirstRange.lowerBound..<vndEndRange.lowerBound]

        var parameters = [String: String]()
        vndParameters.split(separator: ";").forEach { p in
            guard let equalIndex = p.firstIndex(of: "=") else { return }
            parameters[String(p[p.startIndex..<equalIndex])] = String(p[p.index(after: equalIndex)..<p.endIndex])
        }

        guard let readerName = parameters["vndYabr_readerName"] ?? parameters["vnd_readerName"] else { return nil }

        self.id = entry.device
        self.readerName = readerName

        if let vndYabr_maxPage = parameters["vndYabr_maxPage"] ?? parameters["vnd_maxPage"], let maxPage = Int(vndYabr_maxPage) {
            self.maxPage = maxPage
        }
        if let vndYabr_lastReadPage = parameters["vndYabr_lastReadPage"] ?? parameters["vnd_lastReadPage"], let lastReadPage = Int(vndYabr_lastReadPage) {
            self.lastReadPage = lastReadPage
        }
        if let vndYabr_lastReadChapter = parameters["vndYabr_lastReadChapter"] ?? parameters["vnd_lastReadChapter"] {
            self.lastReadChapter = vndYabr_lastReadChapter
        }
        if let vndYabr_lastChapterProgress = parameters["vndYabr_lastChapterProgress"] ?? parameters["vnd_lastChapterProgress"], let lastChapterProgress = Double(vndYabr_lastChapterProgress) {
            self.lastChapterProgress = lastChapterProgress
        }
        if let vndYabr_lastProgress = parameters["vndYabr_lastProgress"] ?? parameters["vnd_lastProgress"], let lastProgress = Double(vndYabr_lastProgress) {
            self.lastProgress = lastProgress
        }
        if let vndYabr_furthestReadPage = parameters["vndYabr_furthestReadPage"] ?? parameters["vnd_furthestReadPage"], let furthestReadPage = Int(vndYabr_furthestReadPage) {
            self.furthestReadPage = furthestReadPage
        }
        if let vndYabr_furthestReadChapter = parameters["vndYabr_furthestReadChapter"] ?? parameters["vnd_furthestReadChapter"] {
            self.furthestReadChapter = vndYabr_furthestReadChapter
        }
        if let vndYabr_epoch = parameters["vndYabr_epoch"] ?? parameters["vnd_epoch"], let epoch = Double(vndYabr_epoch), epoch > 0.0 {
            self.epoch = epoch
        } else if entry.epoch > 0.0 {
            self.epoch = entry.epoch
        } else {
            self.epoch = Date().timeIntervalSince1970
        }
        if let vndYabr_lastPosition = parameters["vndYabr_lastPosition"] ?? parameters["vnd_lastPosition"] {
            let positions = vndYabr_lastPosition.split(separator: ".").compactMap { Int($0) }
            if positions.count == 3 {
                self.lastPosition = positions
            }
        }
        if let vndYabr_structuralStyle = parameters["vndYabr_structuralStyle"],
           let structuralStyle = Int(vndYabr_structuralStyle) {
            self.structuralStyle = structuralStyle
        }
        if let vndYabr_structuralRootPageNumber = parameters["vndYabr_structuralRootPageNumber"],
           let structuralRootPageNumber = Int(vndYabr_structuralRootPageNumber) {
            self.structuralRootPageNumber = structuralRootPageNumber
        }
        if let vndYabr_positionTrackingStyle = parameters["vndYabr_positionTrackingStyle"],
           let positionTrackingStyle = Int(vndYabr_positionTrackingStyle) {
            self.positionTrackingStyle = positionTrackingStyle
        }
        if let vndYabr_lastReadBook = parameters["vndYabr_lastReadBook"] {
            self.lastReadBook = vndYabr_lastReadBook
        }
        if let vndYabr_lastBundleProgress = parameters["vndYabr_lastBundleProgress"],
           let lastBundleProgress = Double(vndYabr_lastBundleProgress) {
            self.lastBundleProgress = lastBundleProgress
        }

        self.cfi = String(entry.cfi[entry.cfi.startIndex..<vndFirstRange.lowerBound] + entry.cfi[vndEndRange.lowerBound..<entry.cfi.endIndex]).replacingOccurrences(of: "[]", with: "")
    }

    func encodeEPUBCFI() -> String {
        var parameters = [String: String]()
        parameters["vndYabr_readerName"] = readerName
        parameters["vndYabr_maxPage"] = maxPage.description
        parameters["vndYabr_lastReadPage"] = lastReadPage.description
        parameters["vndYabr_lastReadChapter"] = lastReadChapter
        parameters["vndYabr_lastChapterProgress"] = lastChapterProgress.description
        parameters["vndYabr_lastProgress"] = lastProgress.description
        parameters["vndYabr_furthestReadPage"] = furthestReadPage.description
        parameters["vndYabr_furthestReadChapter"] = furthestReadChapter
        parameters["vndYabr_lastPosition"] = lastPosition.map { $0.description }.joined(separator: ".")
        if epoch > 0.0 {
            parameters["vndYabr_epoch"] = epoch.description
        } else {
            parameters["vndYabr_epoch"] = Date().timeIntervalSince1970.description
        }
        parameters["vndYabr_structuralStyle"] = structuralStyle.description
        parameters["vndYabr_structuralRootPageNumber"] = structuralRootPageNumber.description
        parameters["vndYabr_positionTrackingStyle"] = positionTrackingStyle.description
        parameters["vndYabr_lastReadBook"] = lastReadBook
        parameters["vndYabr_lastBundleProgress"] = lastBundleProgress.description

        let vndParameters = parameters.map {
            "\($0.key)=\($0.value.replacingOccurrences(of: ",|;|=|\\[|\\]|\\s", with: ".", options: .regularExpression))"
        }.sorted().joined(separator: ";")

        var cfi = cfi
        if cfi.isEmpty || cfi == "/" {
            let typeKey = (ReaderType(rawValue: readerName) ?? .UNSUPPORTED).format.rawValue.lowercased()
            cfi = "\(typeKey)cfi(/\(lastReadPage * 2))"
        }

        var insertIndex = cfi.endIndex
        var insertFragment = "[;\(vndParameters)]"
        if cfi.hasSuffix("])") {
            insertIndex = cfi.index(cfi.endIndex, offsetBy: -2, limitedBy: cfi.startIndex) ?? cfi.startIndex
            insertFragment = ";\(vndParameters)"
        } else if cfi.hasSuffix(")") {
            insertIndex = cfi.index(cfi.endIndex, offsetBy: -1, limitedBy: cfi.startIndex) ?? cfi.startIndex
        }
        cfi.insert(contentsOf: insertFragment, at: insertIndex)

        return cfi
    }

    func toEntry() -> CalibreBookLastReadPositionEntry {
        .init(
            device: id,
            cfi: encodeEPUBCFI(),
            epoch: epoch,
            pos_frac: lastProgress / 100.0
        )
    }
}
