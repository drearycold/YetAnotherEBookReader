//
//  WARNING: Mapper methods in this file must return detached domain value objects.
//  Do not propagate live, thread-confined Realm objects across thread boundaries.
//  When updating managed Realm objects, ensure write operations and primary key guards
//  are handled strictly within write transactions in repository/cache scopes.
//

import Foundation
import RealmSwift

extension CalibreServerRealm {
    func toDomain() -> CalibreServer {
        return CalibreServer(
            uuid: UUID(uuidString: self.primaryKey ?? "") ?? .init(),
            name: self.name ?? self.baseUrl!,
            baseUrl: self.baseUrl!,
            hasPublicUrl: self.hasPublicUrl,
            publicUrl: self.publicUrl ?? "",
            hasAuth: self.hasAuth,
            username: self.username ?? "",
            password: self.password ?? "",
            defaultLibrary: self.defaultLibrary ?? ""
        )
    }

    func applyDomain(_ server: CalibreServer) {
        self.name = server.name
        self.baseUrl = server.baseUrl
        self.hasPublicUrl = server.hasPublicUrl
        self.publicUrl = server.publicUrl
        self.hasAuth = server.hasAuth
        self.username = server.username
        self.password = server.password
        self.defaultLibrary = server.defaultLibrary
        self.removed = server.removed
        if self.realm == nil {
            self.primaryKey = server.uuid.uuidString
        }
    }
}

extension CalibreServer {
    func makeRealmObject() -> CalibreServerRealm {
        let serverRealm = CalibreServerRealm()
        serverRealm.applyDomain(self)
        return serverRealm
    }
}

extension CalibreLibraryRealm {
    func toDomain(server: CalibreServer) -> CalibreLibrary {
        let name = self.name ?? ""
        let customColumnInfos: [String: CalibreCustomColumnInfo] = {
            guard let data = self.customColumnsData else { return [:] }
            return (try? JSONDecoder().decode([String: CalibreCustomColumnInfo].self, from: data)) ?? [:]
        }()
        return CalibreLibrary(
            server: server,
            key: self.key ?? name,
            name: name,
            autoUpdate: self.autoUpdate,
            discoverable: self.discoverable,
            hidden: self.hidden,
            lastModified: self.lastModified,
            customColumnInfos: customColumnInfos
        )
    }

    func applyDomain(_ library: CalibreLibrary) {
        if self.realm == nil {
            self.key = library.key
            self.name = library.name
            self.serverUUID = library.server.uuid.uuidString
        }
        self.customColumnsData = try? JSONEncoder().encode(library.customColumnInfos)
        self.autoUpdate = library.autoUpdate
        self.discoverable = library.discoverable
        self.hidden = library.hidden
        self.lastModified = library.lastModified
    }
}

extension CalibreLibrary {
    func makeRealmObject() -> CalibreLibraryRealm {
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.applyDomain(self)
        return libraryRealm
    }
}

extension CalibreBookRealm {
    func toDomain(library: CalibreLibrary) -> CalibreBook {
        let formatsVer1 = self.formats().reduce(
            into: [String: FormatInfo]()
        ) { result, entry in
            result[entry.key] = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
        }
        let decoder = JSONDecoder()
        let formatsVer2 = (try? decoder.decode([String:FormatInfo].self, from: self.formatsData as Data? ?? .init()))
                ?? formatsVer1
        
        var book = CalibreBook(id: self.idInLib, library: library)
        book.title = self.title
        book.comments = self.comments
        book.publisher = self.publisher
        book.series = self.series
        book.seriesIndex = self.seriesIndex
        book.rating = self.rating
        book.size = self.size
        book.pubDate = self.pubDate
        book.timestamp = self.timestamp
        book.lastModified = self.lastModified
        book.lastSynced = self.lastSynced
        book.lastUpdated = self.lastUpdated
        book.formats = formatsVer2
        book.inShelf = self.inShelf
        
        if self.identifiersData != nil {
            book.identifiers = self.identifiers()
        }
        if self.userMetaData != nil {
            book.userMetadatas = self.userMetadatas()
        }
        
        var parsedAuthors = [String]()
        if let authorFirst = self.authorFirst {
            parsedAuthors.append(authorFirst)
        }
        if let authorSecond = self.authorSecond {
            parsedAuthors.append(authorSecond)
        }
        if let authorThird = self.authorThird {
            parsedAuthors.append(authorThird)
        }
        parsedAuthors.append(contentsOf: self.authorsMore)
        book.authors = parsedAuthors
        
        var parsedTags = [String]()
        if let tagFirst = self.tagFirst {
            parsedTags.append(tagFirst)
        }
        if let tagSecond = self.tagSecond {
            parsedTags.append(tagSecond)
        }
        if let tagThird = self.tagThird {
            parsedTags.append(tagThird)
        }
        parsedTags.append(contentsOf: self.tagsMore)
        book.tags = parsedTags
        
        return book
    }

    func applyDomain(_ book: CalibreBook) {
        if self.realm == nil {
            self.serverUUID = book.library.server.uuid.uuidString
            self.libraryName = book.library.name
            self.idInLib = book.id
        }
        
        self.title = book.title
        
        var authors = book.authors
        self.authorFirst = authors.popFirst() ?? "Unknown"
        self.authorSecond = authors.popFirst()
        self.authorThird = authors.popFirst()
        self.authorsMore.replaceAll(authors)
        
        self.comments = book.comments
        self.publisher = book.publisher
        self.series = book.series
        self.seriesIndex = book.seriesIndex
        self.rating = book.rating
        self.size = book.size
        self.pubDate = book.pubDate
        self.timestamp = book.timestamp
        self.lastModified = book.lastModified
        self.lastSynced = book.lastSynced
        self.lastUpdated = book.lastUpdated
        
        var tags = book.tags
        self.tagFirst = tags.popFirst()
        self.tagSecond = tags.popFirst()
        self.tagThird = tags.popFirst()
        self.tagsMore.replaceAll(tags)
        
        self.inShelf = book.inShelf
        
        let encoder = JSONEncoder()
        self.formatsData = try? encoder.encode(book.formats)
        self.identifiersData = try? encoder.encode(book.identifiers)
        self.userMetaData = try? JSONSerialization.data(withJSONObject: book.userMetadatas, options: [])
        self.readPosData = nil
    }

    func applyMetadataEntry(_ entry: CalibreBookEntry, root: NSDictionary) {
        applyMetadataValue(CalibreBookMetadataValue(entry: entry, root: root))
    }

    func applyMetadataValue(_ metadata: CalibreBookMetadataValue) {
        self.title = metadata.title
        self.publisher = metadata.publisher
        self.series = metadata.series
        self.seriesIndex = metadata.seriesIndex
        self.pubDate = metadata.pubDate
        self.timestamp = metadata.timestamp ?? .distantPast
        self.lastModified = metadata.lastModified ?? .distantPast
        self.lastSynced = self.lastModified

        var authors = metadata.authors
        self.authorFirst = authors.popFirst() ?? "Unknown"
        self.authorSecond = authors.popFirst()
        self.authorThird = authors.popFirst()
        self.authorsMore.replaceAll(authors)

        var tags = metadata.tags
        self.tagFirst = tags.popFirst()
        self.tagSecond = tags.popFirst()
        self.tagThird = tags.popFirst()
        self.tagsMore.replaceAll(tags)

        let existingFormats = (try? JSONDecoder().decode(
            [String: FormatInfo].self,
            from: self.formatsData as Data? ?? .init()
        )) ?? [:]
        self.formatsData = try? JSONEncoder().encode(metadata.mergedFormats(with: existingFormats))

        self.size = metadata.size
        self.rating = metadata.rating
        self.identifiersData = try? JSONEncoder().encode(metadata.identifiers)
        self.comments = metadata.comments
        self.userMetaData = try? JSONSerialization.data(
            withJSONObject: metadata.mergedUserMetadatas(with: self.userMetadatas()),
            options: []
        )
        self.lastUpdated = Date()
    }
}

extension CalibreBook {
    func makeRealmObject() -> CalibreBookRealm {
        let bookRealm = CalibreBookRealm()
        bookRealm.applyDomain(self)
        return bookRealm
    }
}
