//
//  DatabaseBootstrapper.swift
//  YetAnotherEBookReader
//
//  Extracted from AppContainer.initializeDatabase() and
//  AppContainer.migrateLegacyReadPosData() on 2026-06-24.
//

import Foundation
import RealmSwift
import Combine
import OSLog

/// Errors thrown by `DatabaseBootstrapper.bootstrap` when the database cannot
/// be initialized. Surfaced to the caller so the upgrade UI can remain
/// visible and the user sees a real failure state.
enum DatabaseBootstrapError: Error {
    case realmOpenFailed(underlying: Error)
}

final class DatabaseBootstrapper {
    private let container: AppContainerProtocol
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "DatabaseBootstrapper")

    init(container: AppContainerProtocol) {
        self.container = container
    }

    /// Boot the database after migration: open the Realm on the main thread,
    /// install the activity logger, wire up the DownloadManager and the
    /// background-save Realm, then trigger initial population of
    /// servers/libraries/books and clean stale activity entries.
    ///
    /// Throws `DatabaseBootstrapError.realmOpenFailed` if the main Realm
    /// cannot be opened. On throw, the caller should leave `AppContainer.realm`
    /// nil so the upgrade UI stays visible.
    func bootstrap(realmConf: Realm.Configuration) throws {
        do {
            container.realm = try Realm(configuration: realmConf)
        } catch {
            logger.error("Failed to open main Realm: \(error.localizedDescription)")
            throw DatabaseBootstrapError.realmOpenFailed(underlying: error)
        }
        container.logger = CalibreActivityLogger(realmConf: realmConf)
        container.calibreServerService.logger = container.logger!
        container.databaseService.setup(conf: realmConf)
        container.downloadManager.setup(container: container, realmConf: realmConf)
        AppContainer.SaveBooksMetadataRealmQueue.sync {
            container.realmSaveBooksMetadata = try? Realm(
                configuration: realmConf, queue: AppContainer.SaveBooksMetadataRealmQueue
            )
        }

        container.serverManager.populateServers()
        container.libraryManager.populateLibraries()
        container.bookManager.populateBookShelf()
        container.libraryManager.populateLocalLibraryBooks()

        container.calibreUpdatedSubject.send(.shelf)
        container.cleanCalibreActivities(startDatetime: Date(timeIntervalSinceNow: TimeInterval(-86400*7)))

        migrateLegacyReadPosData()
    }

    /// Background-task that copies legacy readPosData out of CalibreBookRealm
    /// into the ReadingPositionRepository, then nulls out the legacy field.
    func migrateLegacyReadPosData() {
        let container = self.container
        let logger = self.logger
        DispatchQueue.global(qos: .background).async {
            guard let realmConf = container.realmConf,
                  let realm = try? Realm(configuration: realmConf) else {
                return
            }

            let bookKeysToMigrate = realm.objects(CalibreBookRealm.self)
                .filter("readPosData != nil")
                .compactMap { $0.primaryKey }

            guard !bookKeysToMigrate.isEmpty else { return }

            logger.info("migrateLegacyReadPosData: Found \(bookKeysToMigrate.count) legacy reading positions to migrate.")

            let readingPositionRepository = container.readingPositionRepository

            for key in bookKeysToMigrate {
                guard let realmConf = container.realmConf,
                      let freshRealm = try? Realm(configuration: realmConf),
                      let bookRealm = freshRealm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key),
                      let serverUUID = bookRealm.serverUUID,
                      let libraryName = bookRealm.libraryName
                else {
                    continue
                }

                if let library = container.library(forServerUUID: serverUUID, libraryName: libraryName) {
                    bookRealm.migrateReadPos(library: library, repository: readingPositionRepository)
                }

                try? freshRealm.write {
                    bookRealm.readPosData = nil
                }
            }

            logger.info("migrateLegacyReadPosData: Completed background migration of legacy reading positions.")
        }
    }
}
