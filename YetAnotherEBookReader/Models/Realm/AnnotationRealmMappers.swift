//
//  WARNING: Mapper methods in this file must return detached domain value objects.
//  Do not propagate live, thread-confined Realm objects across thread boundaries.
//  When updating managed Realm objects, ensure write operations and primary key guards
//  are handled strictly within write transactions in repository/cache scopes.
//

import Foundation
import RealmSwift

extension BookBookmarkRealm {
    func toDomain() -> BookBookmark {
        return BookBookmark(
            id: self._id.stringValue,
            bookId: self.bookId,
            page: self.page,
            pos_type: self.pos_type,
            pos: self.pos,
            title: self.title,
            date: self.date,
            removed: self.removed
        )
    }

    func applyDomain(_ domain: BookBookmark) {
        if self.realm == nil, let objectId = try? ObjectId(string: domain.id) {
            self._id = objectId
        }
        self.bookId = domain.bookId
        self.page = domain.page
        self.pos_type = domain.pos_type
        self.pos = domain.pos
        self.title = domain.title
        self.date = domain.date
        self.removed = domain.removed
    }
}

extension BookBookmark {
    func makeRealmObject() -> BookBookmarkRealm {
        let object = BookBookmarkRealm()
        object.applyDomain(self)
        return object
    }
}

extension BookHighlightRealm {
    func toDomain() -> BookHighlight {
        return BookHighlight(
            id: self.highlightId,
            bookId: self.bookId,
            readerName: self.readerName,
            page: self.page,
            startOffset: self.startOffset,
            endOffset: self.endOffset,
            date: self.date,
            type: self.type,
            note: self.note,
            tocFamilyTitles: Array(self.tocFamilyTitles),
            content: self.content,
            contentPost: self.contentPost,
            contentPre: self.contentPre,
            cfiStart: self.cfiStart,
            cfiEnd: self.cfiEnd,
            spineName: self.spineName,
            ranges: self.ranges,
            removed: self.removed
        )
    }

    func applyDomain(_ domain: BookHighlight) {
        if self.realm == nil {
            self.highlightId = domain.id
        }
        self.bookId = domain.bookId
        self.readerName = domain.readerName
        self.page = domain.page
        self.startOffset = domain.startOffset
        self.endOffset = domain.endOffset
        self.date = domain.date
        self.type = domain.type
        self.note = domain.note
        self.tocFamilyTitles.replaceAll(domain.tocFamilyTitles)
        self.content = domain.content
        self.contentPost = domain.contentPost
        self.contentPre = domain.contentPre
        self.cfiStart = domain.cfiStart
        self.cfiEnd = domain.cfiEnd
        self.spineName = domain.spineName
        self.ranges = domain.ranges
        self.removed = domain.removed
    }
}

extension BookHighlight {
    func makeRealmObject() -> BookHighlightRealm {
        let object = BookHighlightRealm()
        object.applyDomain(self)
        return object
    }
}
