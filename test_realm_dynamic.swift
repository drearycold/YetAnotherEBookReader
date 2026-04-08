import Foundation
import RealmSwift

func test(migration: Migration) {
    migration.enumerateObjects(ofType: "Test") { oldObject, newObject in
        if let plugin = oldObject?["plugin"] as? MigrationObject {
            print("MigrationObject works")
        }
        if let plugin = oldObject?["plugin"] as? DynamicObject {
            print("DynamicObject works")
        }
    }
}
