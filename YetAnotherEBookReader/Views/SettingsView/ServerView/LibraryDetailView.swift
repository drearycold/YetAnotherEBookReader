//
//  LibraryDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2022/2/14.
//

import SwiftUI
import RealmSwift

struct LibraryDetailView: View {
    @EnvironmentObject var modelData: ModelData

    @ObservedResults(CalibreBookRealm.self, configuration: ModelData.shared?.realmConf) var books
    
    var library: CalibreLibrary
    @ObservedRealmObject var libraryRealm: CalibreLibraryRealm

    @State private var activityListViewPresenting = false
    @State private var updater = 0

    @State private var isStoreActive = false
    
    var body: some View {
        Form {
            Section(header: Text("Browsable")) {
                Toggle("Include in Discover", isOn: $libraryRealm.discoverable)
                
                Toggle("Available when Offline", isOn: $libraryRealm.autoUpdate)
            }
            
            Section(header: Text("Troubleshooting")) {
                NavigationLink(
                    destination: ActivityList(presenting: Binding<Bool>(get: { false }, set:{_ in }), libraryId: library.id, bookId: nil)
                ) {
                    Text("Activity Logs")
                }
                if let err = modelData.librarySyncStatus[library.id]?.err, err.isEmpty == false {
                    NavigationLink {
                        List {
                            ForEach(err.map { $0 }.sorted(), id: \.self) { bookId in
                                HStack {
                                    Text(bookId.description)
                                    
                                    if let obj = modelData.getBookRealm(forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: library.server.uuid.uuidString, libraryName: library.name, id: bookId.description)) {
                                        Spacer()
                                        Text(obj.title)
                                    }
                                }
                            }
                        }.navigationTitle(Text("Book IDs Failed to Sync"))
                    } label: {
                        Text("Book IDs Failed to Sync")
                    }
                }
                if let del = modelData.librarySyncStatus[library.id]?.del, del.isEmpty == false {
                    NavigationLink {
                        List {
                            ForEach(del.map { $0 }.sorted(), id: \.self) { bookId in
                                HStack {
                                    Text(bookId.description)
                                    
                                    if let obj = modelData.getBookRealm(forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: library.server.uuid.uuidString, libraryName: library.name, id: bookId.description)) {
                                        Spacer()
                                        Text(obj.title)
                                    }
                                }
                            }
                        }.navigationTitle(Text("Book IDs Deleted on Server"))
                    } label: {
                        Text("Book IDs Deleted on Server")
                    }
                }
            }
            
            #if DEBUG
            Section {
                Button("Reset Books") {
                    try! modelData.realm.write {
                        modelData.realm.objects(CalibreBookRealm.self).forEach {
                            $0.lastModified = .init(timeIntervalSince1970: 0)
                            $0.lastSynced = .init(timeIntervalSince1970: 0)
                            $0.title = "__RESET__"
                        }
                    }
                }
            } header: {
                Text("OP")
            }
            
            Section {
                Text("isSync: \((modelData.librarySyncStatus[library.id]?.isSync ?? false) ? "true" : "false")")
                Text("isUpd: \((modelData.librarySyncStatus[library.id]?.isUpd ?? false) ? "true" : "false")")
                Text("isError: \((modelData.librarySyncStatus[library.id]?.isError ?? false) ? "true" : "false")")
                Text("MSG: \(modelData.librarySyncStatus[library.id]?.msg ?? "nil")")
                Text("CNT: \(modelData.librarySyncStatus[library.id]?.cnt ?? -1)")
                Text("UPD: \(modelData.librarySyncStatus[library.id]?.upd.count ?? -1)")
                Text("DEL: \(modelData.librarySyncStatus[library.id]?.del.count ?? -1)")
                Text("ERR: \(modelData.librarySyncStatus[library.id]?.err.count ?? -1)")
            } header: {
                Text("DEBUG")
            }
            #endif
        }
    }

}

struct LibraryDetailView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var library = modelData.calibreLibraries.values.first ?? .init(server: .init(uuid: .init(), name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default"), key: "Default", name: "Default")

    @State static private var discoverable = false
    @State static private var autoUpdate = false
    
    static var previews: some View {
        let libraryRealm = modelData.realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id) ?? CalibreLibraryRealm()
        return NavigationView {
            LibraryDetailView(
                library: library,
                libraryRealm: libraryRealm
            )
            .environmentObject(modelData)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
