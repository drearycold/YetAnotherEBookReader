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
        Form {
            Section(header: Text("Behavior")) {
                Toggle("Include in Discover", isOn: $discoverable)
                
                Toggle("Keep in Sync with Server", isOn: $autoUpdate)
            }
            
            Section(header: Text("More Customizations")) {
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
                    ).navigationTitle("\(library.name) - Reading Positions")
                    ,
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
                    .navigationTitle("\(library.name) - Custom Column Mappings")
                ) {
                    Text("Custom Column Mappings")
                }
            }
            
            Section(header: Text("Troubleshooting")) {
                NavigationLink(
                    destination: ActivityList(presenting: Binding<Bool>(get: { false }, set:{_ in }), libraryId: library.id, bookId: nil)
                ) {
                    Text("Activity Logs")
                }
            }
        }
        
    }

}

struct LibraryDetailView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var library = modelData.calibreLibraries.values.first ?? .init(server: .init(uuid: .init(), name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default"), key: "Default", name: "Default")

    @State static private var discoverable = false
    @State static private var autoUpdate = false
    static var previews: some View {
        NavigationView {
            LibraryDetailView(library: $library, discoverable: $discoverable, autoUpdate: $autoUpdate)
                .environmentObject(modelData)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
