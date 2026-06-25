//
//  DatabaseBootstrapper.swift
//  YetAnotherEBookReader
//
//  Extracted from ModelData.initializeDatabase() and
//  ModelData.migrateLegacyReadPosData() on 2026-06-24.
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
    private let modelData: AppContainerProtocol
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "DatabaseBootstrapper")

    init(modelData: AppContainerProtocol) {
        self.modelData = modelData
    }

    /// Boot the database after migration: open the Realm on the main thread,
    /// install the activity logger, wire up the DownloadManager and the
    /// background-save Realm, then trigger initial population of
    /// servers/libraries/books and clean stale activity entries.
    ///
    /// Throws `DatabaseBootstrapError.realmOpenFailed` if the main Realm
    /// cannot be opened. On throw, the caller should leave `ModelData.realm`
    /// nil so the upgrade UI stays visible.
    func bootstrap(realmConf: Realm.Configuration) throws {
        do {
            modelData.realm = try Realm(configuration: realmConf)
        } catch {
            logger.error("Failed to open main Realm: \(error.localizedDescription)")
            throw DatabaseBootstrapError.realmOpenFailed(underlying: error)
        }
        modelData.logger = CalibreActivityLogger(realmConf: realmConf)
        modelData.calibreServerService.logger = modelData.logger!
        modelData.databaseService.setup(conf: realmConf)
        modelData.downloadManager.setup(modelData: modelData, realmConf: realmConf)
        ModelData.SaveBooksMetadataRealmQueue.sync {
            modelData.realmSaveBooksMetadata = try? Realm(
                configuration: realmConf, queue: ModelData.SaveBooksMetadataRealmQueue
            )
        }

        modelData.serverManager.populateServers()
        modelData.libraryManager.populateLibraries()
        modelData.bookManager.populateBookShelf()
        modelData.libraryManager.populateLocalLibraryBooks()

        modelData.calibreUpdatedSubject.send(.shelf)
        modelData.cleanCalibreActivities(startDatetime: Date(timeIntervalSinceNow: TimeInterval(-86400*7)))

        migrateLegacyReadPosData()
    }

    /// Background-task that copies legacy readPosData out of CalibreBookRealm
    /// into the ReadingPositionRepository, then nulls out the legacy field.
    func migrateLegacyReadPosData() {
        let modelData = self.modelData
        let logger = self.logger
        DispatchQueue.global(qos: .background).async {
            guard let realmConf = modelData.realmConf,
                  let realm = try? Realm(configuration: realmConf) else {
                return
            }

            let bookKeysToMigrate = realm.objects(CalibreBookRealm.self)
                .filter("readPosData != nil")
                .compactMap { $0.primaryKey }

            guard !bookKeysToMigrate.isEmpty else { return }

            logger.info("migrateLegacyReadPosData: Found \(bookKeysToMigrate.count) legacy reading positions to migrate.")

            let readingPositionRepository = modelData.readingPositionRepository

            for key in bookKeysToMigrate {
                guard let realmConf = modelData.realmConf,
                      let freshRealm = try? Realm(configuration: realmConf),
                      let bookRealm = freshRealm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key),
                      let serverUUID = bookRealm.serverUUID,
                      let libraryName = bookRealm.libraryName
                else {
                    continue
                }

                if let library = modelData.library(forServerUUID: serverUUID, libraryName: libraryName) {
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
