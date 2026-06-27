//
//  ReadingPositionModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: reading-position value types and statistics.
//

import Foundation

/*
struct BookReadingPositionLegacy {
    private var deviceMap = [String: BookDeviceReadingPosition]()
    private var devices = [BookDeviceReadingPosition]()
    
    var isEmpty: Bool { get { deviceMap.isEmpty } }
    
    func getPosition(_ deviceName: String) -> BookDeviceReadingPosition? {
        return deviceMap[deviceName]
    }
    
    mutating func addInitialPosition(_ deviceName: String, _ readerName: String) {
        let initialPosition = BookDeviceReadingPosition(id: deviceName, readerName: readerName)
        self.updatePosition(deviceName, initialPosition)
    }
    
    mutating func updatePosition(_ deviceName: String, _ newPosition: BookDeviceReadingPosition) {
        if let oldPosition = deviceMap[deviceName] {
            devices.removeAll { (it) -> Bool in
                it.id == oldPosition.id
            }
        }
        deviceMap[deviceName] = newPosition
        devices.append(newPosition)
        devices.sort { (lhs, rhs) -> Bool in
            
            if lhs.lastPosition[0] == rhs.lastPosition[0] {
                return (lhs.lastPosition[1] + lhs.lastPosition[2]) > (rhs.lastPosition[1] + rhs.lastPosition[2])
            } else {
                return lhs.lastPosition[0] > rhs.lastPosition[0]
            }
        }
    }
    
    mutating func removePosition(_ deviceName: String) {
        deviceMap.removeValue(forKey: deviceName)
        devices.removeAll { position in
            position.id == deviceName
        }
    }
    
    func getCopy() -> [String: BookDeviceReadingPosition] {
        return deviceMap
    }
    
    func getDevices() -> [BookDeviceReadingPosition] {
        return devices
    }
    
    func getDevices(by reader: ReaderType) -> [BookDeviceReadingPosition] {
        return devices.filter {
            $0.readerName == reader.id
        }
    }
}
*/

struct BookDeviceReadingPosition : Hashable, Codable {
    static func == (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        lhs.id == rhs.id
            && lhs.readerName == rhs.readerName
            && lhs.lastReadPage == rhs.lastReadPage
            && lhs.lastProgress == rhs.lastProgress
            && lhs.structuralRootPageNumber == rhs.structuralRootPageNumber
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(readerName)
        hasher.combine(lastReadPage)
        hasher.combine(structuralStyle)
        hasher.combine(positionTrackingStyle)
        hasher.combine(structuralRootPageNumber)
    }
    
    var id: String = ""  //device name
    
    var readerName: String
    
    var maxPage = 0
    var lastReadPage = 0
    var lastReadChapter = ""
    /// range 0 - 100
    var lastChapterProgress = 0.0
    /// range 0 - 100
    var lastProgress = 0.0
    var furthestReadPage = 0
    var furthestReadChapter = ""
    var lastPosition = [0, 0, 0]
    var cfi = "/"
    var epoch = 0.0     //timestamp
    
    //for non-linear book structure
    var structuralStyle: Int = .zero
    var structuralRootPageNumber: Int = .zero
    var positionTrackingStyle: Int = .zero
    var lastReadBook: String = .init()
    var lastBundleProgress: Double = .zero
    
    enum CodingKeys: String, CodingKey {
        case readerName
        case lastReadPage
        case lastReadChapter
        case lastChapterProgress
        case lastProgress
        case furthestReadPage
        case furthestReadChapter
        case maxPage
        case lastPosition
        case cfi
        case epoch
        
        case structuralStyle
        case structuralRootPageNumber
        case positionTrackingStyle
        case lastReadBook
        case lastBundleProgress
    }
    
    var description: String {
        return """
            \(id) with \(readerName):
                Chapter: \(lastReadChapter), \(String(format: "%.2f", 100 - lastChapterProgress))% Left
                Book: Page \(lastReadPage), \(String(format: "%.2f", 100 - lastProgress))% Left
                (\(lastPosition[0]):\(lastPosition[1]):\(lastPosition[2]))
            """
    }
    
    static func < (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        if lhs.lastReadPage < rhs.lastReadPage {
            return true
        } else if lhs.lastReadPage > rhs.lastReadPage {
            return false
        }
        if lhs.lastChapterProgress < rhs.lastChapterProgress {
            return true
        } else if lhs.lastChapterProgress > rhs.lastChapterProgress {
            return false
        }
        if lhs.lastProgress < rhs.lastProgress {
            return true
        }
        return false
    }
    
    static func << (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        if (lhs.lastProgress + 10) < rhs.lastProgress {
            return true
        }
        return false
    }
    
    mutating func update(with other: BookDeviceReadingPosition) {
        maxPage = other.maxPage
        lastReadPage = other.lastReadPage
        lastReadChapter = other.lastReadChapter
        lastChapterProgress = other.lastChapterProgress
        lastProgress = other.lastProgress
        lastPosition = other.lastPosition
        cfi = other.cfi
        epoch = other.epoch
    }
    
    func isSameProgress(with other: BookDeviceReadingPosition) -> Bool {
        if id == other.id,
            readerName == other.readerName,
            lastReadPage == other.lastReadPage,
            lastChapterProgress == other.lastChapterProgress,
            lastProgress == other.lastProgress {
            return true
        }
        return false
    }
    
    func isSameType(with other: BookDeviceReadingPosition) -> Bool {
        return id == other.id && readerName == other.readerName
    }
    
    var epochByLocale: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    
    var epochByLocaleRelative: String {
        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    
    var epochLocaleLong: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}



struct BookDeviceReadingPositionHistory : Hashable, Codable {
    var bookId: String
    
    var startDatetime = Date()
    var startPosition: BookDeviceReadingPosition?
    var endPosition: BookDeviceReadingPosition?
    
    static func == (lhs: BookDeviceReadingPositionHistory, rhs: BookDeviceReadingPositionHistory) -> Bool {
        lhs.bookId == rhs.bookId
        && lhs.endPosition == rhs.endPosition
        // && lhs.startPosition == rhs.startPosition
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bookId)
        hasher.combine(endPosition)
        // hasher.combine(startPosition)
    }
}

extension BookDeviceReadingPositionHistory {
    static func getReadingStatistics(list: [BookDeviceReadingPositionHistory], limitDays: Int) -> [Double] {
        let result = list.reduce(into: [Double].init(repeating: 0.0, count: limitDays+1) ) { result, history in
            guard let epoch = history.endPosition?.epoch, epoch > history.startDatetime.timeIntervalSince1970 else { return }
            let duration = epoch - history.startDatetime.timeIntervalSince1970
            let readDayDate = Calendar.current.startOfDay(for: history.startDatetime)
            let nowDayDate = Calendar.current.startOfDay(for: Date())
            let offset = limitDays - Int(floor(nowDayDate.timeIntervalSince(readDayDate) / 86400.0))
            if offset < 0 || offset > limitDays { return }
            result[offset] += duration / 60
        }
        return result
    }
}

enum ReadingPositionSelectionPolicy: Equatable, Sendable {
    case latest
    case latestForDevice(String)
    
    func select(from positions: [BookDeviceReadingPosition]) -> BookDeviceReadingPosition? {
        switch self {
        case .latest:
            guard !positions.isEmpty else { return nil }
            var best = positions[0]
            for position in positions.dropFirst() {
                if position.epoch > best.epoch {
                    best = position
                }
            }
            return best
            
          case .latestForDevice(let deviceName):
            let devicePositions = positions.filter { $0.id == deviceName }
            guard !devicePositions.isEmpty else { return nil }
            var best = devicePositions[0]
            for position in devicePositions.dropFirst() {
                if position.epoch > best.epoch {
                    best = position
                }
            }
            return best
        }
    }
}
