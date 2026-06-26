//
//  DefaultServerScopedRealmConfigurationProvider.swift
//  YetAnotherEBookReader
//
//  Production implementation of `ServerScopedRealmConfigurationProviding`.
//  Delegates to `BookAnnotation.getBookPreferenceServerConfig(_:)`, which
//  is the long-standing default that writes a per-server `.realm` file
//  into Application Support.
//

import Foundation
import RealmSwift

final class DefaultServerScopedRealmConfigurationProvider: ServerScopedRealmConfigurationProviding {
    func configuration(for server: CalibreServer) -> Realm.Configuration {
        BookAnnotation.getBookPreferenceServerConfig(server)
    }
}
