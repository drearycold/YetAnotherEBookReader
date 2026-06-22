//
//  WARNING: Mapper methods in this file must return detached domain value objects.
//  Do not propagate live, thread-confined Realm objects across thread boundaries.
//  When updating managed Realm objects, ensure write operations and primary key guards
//  are handled strictly within write transactions in repository/cache scopes.
//

import Foundation
import RealmSwift

extension BookDeviceReadingPositionRealm {
    func toDomain() -> BookDeviceReadingPosition {
        return BookDeviceReadingPosition(
            id: self.deviceId,
            readerName: self.readerName,
            maxPage: self.maxPage,
            lastReadPage: self.lastReadPage,
            lastReadChapter: self.lastReadChapter,
            lastChapterProgress: self.lastChapterProgress,
            lastProgress: self.lastProgress,
            furthestReadPage: self.furthestReadPage,
            furthestReadChapter: self.furthestReadChapter,
            lastPosition: self.lastPosition.map { $0 },
            cfi: self.cfi,
            epoch: self.epoch,
            structuralStyle: self.structuralStyle,
            structuralRootPageNumber: self.structuralRootPageNumber,
            positionTrackingStyle: self.positionTrackingStyle,
            lastReadBook: self.lastReadBook,
            lastBundleProgress: self.lastBundleProgress
        )
    }

    func applyDomain(_ domain: BookDeviceReadingPosition, bookId: String) {
        if self.realm == nil {
            self.bookId = bookId
            self.deviceId = domain.id
            self.readerName = domain.readerName
        }
        self.maxPage = domain.maxPage
        self.lastReadPage = domain.lastReadPage
        self.lastReadChapter = domain.lastReadChapter
        self.lastChapterProgress = domain.lastChapterProgress
        self.lastProgress = domain.lastProgress
        self.furthestReadPage = domain.furthestReadPage
        self.furthestReadChapter = domain.furthestReadChapter
        self.lastPosition.replaceAll(domain.lastPosition)
        self.cfi = domain.cfi
        self.epoch = domain.epoch
        
        self.structuralStyle = domain.structuralStyle
        self.structuralRootPageNumber = domain.structuralRootPageNumber
        self.positionTrackingStyle = domain.positionTrackingStyle
        self.lastReadBook = domain.lastReadBook
        self.lastBundleProgress = domain.lastBundleProgress
    }
}

extension BookDeviceReadingPosition {
    func makeRealmObject(bookId: String) -> BookDeviceReadingPositionRealm {
        let obj = BookDeviceReadingPositionRealm()
        obj.applyDomain(self, bookId: bookId)
        return obj
    }
}

extension BookDeviceReadingPositionHistoryRealm {
    func toDomain() -> BookDeviceReadingPositionHistory {
        var startPos: BookDeviceReadingPosition? = nil
        var endPos: BookDeviceReadingPosition? = nil
        if let startPosition = self.startPosition {
            startPos = startPosition.toDomain()
        }
        if let endPosition = self.endPosition {
            endPos = endPosition.toDomain()
        }
        return BookDeviceReadingPositionHistory(
            bookId: self.bookId,
            startDatetime: self.startDatetime,
            startPosition: startPos,
            endPosition: endPos
        )
    }

    func applyDomain(_ domain: BookDeviceReadingPositionHistory) {
        if self.realm == nil {
            self.bookId = domain.bookId
            self.startDatetime = domain.startDatetime
        }
        
        if let startDomain = domain.startPosition {
            if let existingStart = self.startPosition {
                existingStart.applyDomain(startDomain, bookId: domain.bookId)
            } else {
                let newStart = BookDeviceReadingPositionRealm()
                newStart.applyDomain(startDomain, bookId: domain.bookId)
                self.startPosition = newStart
            }
        } else {
            self.startPosition = nil
        }
        
        if let endDomain = domain.endPosition {
            if let existingEnd = self.endPosition {
                existingEnd.applyDomain(endDomain, bookId: domain.bookId)
            } else {
                let newEnd = BookDeviceReadingPositionRealm()
                newEnd.applyDomain(endDomain, bookId: domain.bookId)
                self.endPosition = newEnd
            }
        } else {
            self.endPosition = nil
        }
    }
}

extension BookDeviceReadingPositionHistory {
    func makeRealmObject() -> BookDeviceReadingPositionHistoryRealm {
        let object = BookDeviceReadingPositionHistoryRealm()
        object.applyDomain(self)
        return object
    }
}
