//
//  CalibreServerConfigProvider.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: the CalibreServerConfigProvider protocol used to
//  bridge managers/services with the AppContainer facade.
//

import Foundation

protocol CalibreServerConfigProvider: AnyObject {
    var deviceName: String { get }
    var calibreLibraries: [String: CalibreLibrary] { get }
    var librarySyncStatus: [String: CalibreSyncStatus] { get set }
    var calibreServerInfoStaging: [String: CalibreServerInfo] { get }

    var updatingMetadata: Bool { get set }
    var updatingMetadataStatus: String { get set }
    var updatingMetadataSucceed: Bool { get set }

    func updateBook(book: CalibreBook)
    func getPreferredFormat(for book: CalibreBook) -> Format?
}
