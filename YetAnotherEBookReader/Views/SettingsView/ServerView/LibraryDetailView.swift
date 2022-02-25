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

    @State var dsreaderHelperServer = CalibreServerDSReaderHelper(id: "", port: 0)
//    @State var dsreaderHelperLibrary = CalibreLibraryDSReaderHelper()
    //@State var readingPosition = CalibreLibraryReadingPosition()
    //@State var goodreadsSync = CalibreLibraryGoodreadsSync()
    @State var countPages = CalibreLibraryCountPages()
    
    @State private var configuration: CalibreDSReaderHelperConfiguration? = nil
    @State private var overrideMappingPresenting = false

    @State private var activityListViewPresenting = false
    @State private var updater = 0

    @State private var isStoreActive = false
    
    var body: some View {
        List {
            Toggle("Include in Discover", isOn: $library.discoverable)
            
            Toggle("Auto Update with Server", isOn: $library.autoUpdate)
            
            Group {
                Text("More Customizations")
                    .font(.headline)
                    .padding([.top], 16)
                
                NavigationLink(
                    destination: LibraryOptionsReadingPosition(
                        library: library,
                        dsreaderHelperServer: Binding<CalibreServerDSReaderHelper>(
                            get: {
                                modelData.queryServerDSReaderHelper(server: library.server) ?? .init(id: library.server.id, port: 0)
                            },
                            set: { _ in }
                        ),
                        readingPosition: Binding<CalibreLibraryReadingPosition>(
                            get: {
                                return library.pluginReadingPositionWithDefault ?? .init()
                            },
                            set: { readingPosition in
                                if library.pluginReadingPositionWithDefault != readingPosition {
                                    var newValue = readingPosition
                                    newValue._isOverride = true
                                    if let newLibrary = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: newValue) {
                                        library = newLibrary
                                    }
                                }
                            }
                        ),
                        dsreaderHelperLibrary: Binding<CalibreLibraryDSReaderHelper>(
                            get: {
                                return library.pluginDSReaderHelperWithDefault ?? .init()
                            },
                            set: { dsreaderHelperLibrary in
                                if library.pluginDSReaderHelperWithDefault != dsreaderHelperLibrary {
                                    var newValue = dsreaderHelperLibrary
                                    newValue._isOverride = true
                                    if let newLibrary = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: newValue) {
                                        library = newLibrary
                                    }
                                }
                            }
                        ),
                        goodreadsSync: Binding<CalibreLibraryGoodreadsSync>(
                            get: {
                                return library.pluginGoodreadsSyncWithDefault ?? .init()
                            },
                            set: { _ in }
                        )
                    ),
                    isActive: $isStoreActive) {
                    Text("Reading Positions")
                }
                
//                NavigationLink(
//                    destination: goodreadsSyncAutomationView()
//                ) {
//                    Text("Goodreads Sync Automation")
//                }
//
                NavigationLink(
                    destination: LibraryOptionsOverrideCustomColumnMappings(
                        library: library,
                        configuration: modelData.queryServerDSReaderHelper(server: library.server)?.configuration ?? .init(),
                        goodreadsSync: Binding<CalibreLibraryGoodreadsSync>(
                            get: {
                                return library.pluginGoodreadsSyncWithDefault ?? .init()
                            },
                            set: { newGoodreadsSync in
                                if library.pluginGoodreadsSyncWithDefault != newGoodreadsSync {
                                    var newValue = newGoodreadsSync
                                    newValue._isOverride = true
                                    if let newLibrary = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: newValue) {
                                        library = newLibrary
                                    }
                                }
                            }
                        ),
                        countPages: Binding<CalibreLibraryCountPages>(
                            get: {
                                return library.pluginCountPagesWithDefault ?? .init()
                            },
                            set: { newCountPage in
                                if library.pluginCountPagesWithDefault != newCountPage {
                                    var newValue = newCountPage
                                    newValue._isOverride = true
                                    if let newLibrary = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: newValue) {
                                        library = newLibrary
                                    }
                                }
                            }
                        )
                    )
                ) {
                    Text("Custom Column Mappings")
                }
            }
            
            Group {
                Text("Troubleshooting")
                    .font(.headline)
                    .padding([.top], 16)
                NavigationLink(
                    destination: ActivityList(libraryId: library.id, bookId: nil)
                ) {
                    Text("Activity Logs")
                }
            }
        }
        .navigationTitle(library.name)
    }
    
    private func setStates(libraryId: String) {
//        readingPosition = library.pluginReadingPositionWithDefault ?? .init()
        //dsreaderHelperLibrary = library.pluginDSReaderHelperWithDefault ?? .init()
        countPages = library.pluginCountPagesWithDefault ?? .init()
//        goodreadsSync = library.pluginGoodreadsSyncWithDefault ?? .init()

    }
    
//    @ViewBuilder
//    private func storeReadingPositionView() -> some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Toggle("Store Reading Positions in Custom Column", isOn: $readingPosition._isEnabled)
//
//            VStack(alignment: .leading, spacing: 4) {
//                if library.customColumnInfos.filter{ $1.datatype == "comments" }.count > 0 {
//                    Picker("Column Name:     \(readingPosition.readingPositionCN)", selection: $readingPosition.readingPositionCN) {
//                        ForEach(library.customColumnInfoCommentsKeys
//                                    .map{ ($0.name, "#" + $0.label) }, id: \.1) {
//                            Text("\($1)\n\($0)").tag($1)
//                        }
//                    }.pickerStyle(MenuPickerStyle())
//                    .disabled(!readingPosition.isEnabled())
//                } else {
//                    Text("no available column, please refresh library after adding column to calibre").font(.caption).foregroundColor(.red)
//                }
//            }
//        }.onChange(of: readingPosition) { [readingPosition] value in
//            print("readingPosition change from \(readingPosition) to \(value)")
//            if modelData.calibreLibraries[library.id]?.pluginReadingPositionWithDefault != value {
//                var newValue = value
//                newValue._isOverride = true
//                let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: newValue)
//            }
//        }
//    }
    
//    @ViewBuilder
//    private func goodreadsSyncAutomationView() -> some View {
//        VStack(alignment: .leading, spacing: 4) {
//            Toggle("Goodreads Sync Automation", isOn: $dsreaderHelperLibrary._isEnabled)
//
//            Group {
//                HStack {
//                    if let names = dsreaderHelperServer.configuration?.goodreads_sync_prefs?.plugin_prefs.Users.map{ $0.key }.sorted() {
//                        Picker("Profile Name:     \(goodreadsSync.profileName)", selection: $goodreadsSync.profileName) {
//                            ForEach(names, id: \.self) { name in
//                                Text(name)
//                            }
//                        }
//                        .pickerStyle(MenuPickerStyle())
//                    } else {
//                        Text("Empty Profile List")
//                    }
//                }
//
//                Toggle("Auto Update Reading Progress", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsProgress)
//
//                Toggle("Auto Update Book Shelf", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf)
//            }
//            .padding([.leading, .trailing], 8)
//            .disabled( !dsreaderHelperLibrary.isEnabled() )
//
//            if !(dsreaderHelperServer.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.goodreadsSyncEnabled ?? false) {
//                HStack {
//                    Spacer()
//                    Text("Plugin not available").font(.caption).foregroundColor(.red)
//                }
//            }
//        }
//        .onChange(of: dsreaderHelperLibrary) { [dsreaderHelperLibrary] value in
//            print("dsreaderHelperLibrary change from \(dsreaderHelperLibrary) to \(value)")
//            if modelData.calibreLibraries[library.id]?.pluginDSReaderHelperWithDefault != value {
//                let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: value)
//            }
//        }
//        .disabled(
//            !(dsreaderHelperServer.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.goodreadsSyncEnabled ?? false)
//        )
//    }
    
    @ViewBuilder
    private func customColumnMappingsView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
//            LibraryOptionsGoodreadsSync(library: library, configuration: configuration ?? .init(), goodreadsSync: $goodreadsSync)
//                .onChange(of: goodreadsSync, perform: { newValue in
//                    if newValue != modelData.calibreLibraries[library.id]?.pluginGoodreadsSyncWithDefault {
//                        let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: newValue)
//                    }
//                })
//                .onChange(of: countPages) { newValue in
//                    if newValue != modelData.calibreLibraries[library.id]?.pluginCountPagesWithDefault {
//                        let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: countPages)
//                    }
//                }
//            Divider()
//
//            LibraryOptionsCountPages(library: library, configuration: configuration ?? .init(), countPages: $countPages)
        }
    }
}

struct LibraryDetailView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var library = modelData.currentCalibreLibrary ?? .init(server: .init(name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default"), key: "Default", name: "Default")
    
    static var previews: some View {
        NavigationView {
            LibraryDetailView(library: $library)
                .environmentObject(modelData)
        }
    }
}
