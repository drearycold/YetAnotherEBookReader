//
//  RealmListExtensions.swift
//  YetAnotherEBookReader
//

import RealmSwift

extension List {
    public func replaceAll<S: Sequence>(_ elements: S) where S.Element == Element {
        self.removeAll()
        self.append(objectsIn: elements)
    }
}
