//
//  Persistable.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

public protocol Persistable {
    associatedtype ManagedObject: RealmSwift.Object
    init(managedObject: ManagedObject)
    func managedObject() -> ManagedObject
}

extension List {
    public func replaceAll<S: Sequence>(_ elements: S) where S.Element == Element {
        self.removeAll()
        self.append(objectsIn: elements)
    }
}
