//
//  LibraryDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2022/2/14.
//

import SwiftUI

struct LibraryDetailView: View {
    @EnvironmentObject var modelData: ModelData

    @Binding var library: CalibreLibrary
    @Binding var discoverable: Bool
    @Binding var autoUpdate: Bool

    @State var dsreaderHelperServer = CalibreServerDSReaderHelper(id: "", port: 0)
    @Binding var dsreaderHelperLibrary: CalibreLibraryDSReaderHelper
    @Binding var goodreadsSync: CalibreLibraryGoodreadsSync
    @Binding var countPages: CalibreLibraryCountPages
    
    @State private var configuration: CalibreDSReaderHelperConfiguration? = nil
    @State private var overrideMappingPresenting = false

    @State private var activityListViewPresenting = false
    @State private var updater = 0

    @State private var isStoreActive = false
    
    var body: some View {
        Form {
            Section(header: Text("Browsable")) {
                Toggle("Include in Discover", isOn: $discoverable)
                
                Toggle("Available when Offline", isOn: $autoUpdate)
                
                NavigationLink(
                    destination: LibraryOptionsOverrideCustomColumnMappings(
                        library: library,
                        configuration: modelData.queryServerDSReaderHelper(server: library.server)?.configuration ?? .init(),
                        goodreadsSync: $goodreadsSync,
                        countPages: $countPages
                    )
                    .navigationTitle("\(library.name) - Custom Column Mappings")
                ) {
                    Text("Custom Column Mappings")
                }
            }
            
            Section {
                if true == dsreaderHelperServer.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.goodreadsSyncEnabled {
                    Toggle("Enable Automation", isOn: $dsreaderHelperLibrary._isEnabled)
                    
                    Group {
                        HStack {
                            if let names = dsreaderHelperServer.configuration?.goodreads_sync_prefs?.plugin_prefs.Users.map{ $0.key }.sorted() {
                                Picker("Profile Name:     \(goodreadsSync.profileName)", selection: $goodreadsSync.profileName) {
                                    ForEach(names, id: \.self) { name in
                                        Text(name)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            } else {
                                Text("Profile Name:     Empty Profile List")
                            }
                        }
                        
                        Toggle("Auto Update Reading Progress", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsProgress)
                        
                        Toggle("Auto Update Book Shelf", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf)
                    }
                    .disabled( !dsreaderHelperLibrary.isEnabled() )
                } else {
                    Text("Plugin not available").foregroundColor(.red)
                }
            } header: {
                Text("Goodreads Sync")
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
                                    
                                    if let obj = modelData.getBookRealm(forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: library.server.uuid.uuidString, libraryName: library.name, id: bookId.description)),
                                       let title = obj.title {
                                        Spacer()
                                        Text(title)
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
                                    
                                    if let obj = modelData.getBookRealm(forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: library.server.uuid.uuidString, libraryName: library.name, id: bookId.description)),
                                       let title = obj.title {
                                        Spacer()
                                        Text(title)
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
    
    @State static private var dsreaderHelperLibrary = CalibreLibraryDSReaderHelper()
    @State static private var goodreadsSync = CalibreLibraryGoodreadsSync()
    @State static private var countPages = CalibreLibraryCountPages()
    
    static var previews: some View {
        NavigationView {
            LibraryDetailView(
                library: $library,
                discoverable: $discoverable,
                autoUpdate: $autoUpdate,
                dsreaderHelperLibrary: $dsreaderHelperLibrary,
                goodreadsSync: $goodreadsSync,
                countPages: $countPages
            )
            .environmentObject(modelData)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
