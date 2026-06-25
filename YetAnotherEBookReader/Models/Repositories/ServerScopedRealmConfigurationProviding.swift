//
//  ServerScopedRealmConfigurationProviding.swift
//  YetAnotherEBookReader
//
//  Protocol boundary for "per-server sidecar" Realm.Configuration
//  lookups. App code reaches the per-server reading position /
//  reader preference Realm exclusively through this provider, so the
//  test layer can swap the production disk-backed configuration
//  (`DefaultServerScopedRealmConfigurationProvider`) for an in-memory
//  variant without rewriting the call sites.
//

import Foundation
import RealmSwift

protocol ServerScopedRealmConfigurationProviding: AnyObject {
    /// Returns the Realm.Configuration that should be used for the
    /// given CalibreServer's sidecar Realm (reading positions, reader
    /// preferences, etc.). Implementations are free to cache the
    /// result per server.
    func configuration(for server: CalibreServer) -> Realm.Configuration
}
