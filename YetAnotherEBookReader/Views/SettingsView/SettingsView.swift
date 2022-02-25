//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI
import RealmSwift

struct SettingsView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var selectedServer: String? = nil
    
    @State private var addServerActive = false
    @State private var alertItem: AlertItem?

    @State private var serverList = [CalibreServer]()
    @State private var serverListDeleteIndex = 0
    @State private var updater = 0

    var body: some View {
        VStack {
            NavigationView {
                List {
                    Button(action:{
                        updater += 1
                    }) {
                        Text("Refresh")
                    }
                    NavigationLink(
                        destination: AddModServerView(
                            server: Binding<CalibreServer>(get: {
                                .init(name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
                            }, set: { newServer in
                                serverList.append(newServer)
                                sortServerList()
                            }),
                            isActive: $addServerActive)
                            .navigationTitle("Add Server"),
                        isActive: $addServerActive
                    ) {
                        HStack {
                            Text("Connect to a new server")
                            if modelData.booksInShelf.isEmpty {
                                Spacer()
                                Text("Start here")
                                    .foregroundColor(.red)
                                    .font(.caption2)
                            }
                        }
                    }
                    
                    Group {
                        Text("Servers").font(.headline)
                            .padding([.top], 8)
                        ForEach(serverList) { server in
                            NavigationLink (
                                destination: ServerDetailView(server: Binding<CalibreServer>(get: {
                                    server
                                }, set: { [server] newServer in
                                    updateServer(oldServer: server, newServer: newServer)
                                })),
                                tag: server.id,
                                selection: $selectedServer
                            ) {
                                serverRowBuilder(server: server)
                            }
                            .isDetailLink(false)
                        }
                        .onDelete(perform: { indexSet in
                            guard let index = indexSet.first else { return }
                            serverListDeleteIndex = index
                            alertItem = AlertItem(id: "DelServer")
                        })
                        .alert(item: $alertItem) { item in
                            if item.id == "DelServer" {
                                return Alert(
                                    title: Text("Remove Server"),
                                    message: Text("Will Remove Cached Libraries and Books from Reader, Everything on Server will Stay Intact"),
                                    primaryButton: .destructive(Text("Confirm")) {
                                        self.deleteServer()
                                    },
                                    secondaryButton: .cancel()
                                )
                            }
                            return Alert(title: Text("Error"), message: Text(item.id + "\n" + (item.msg ?? "")), dismissButton: .cancel() {
                                item.action?()
                            })
                        }
                    }
                    
                    Group {
                        Text("Options").font(.headline)
                            .padding([.top], 8)
                        NavigationLink("Formats & Readers", destination: ReaderOptionsView())
                        NavigationLink("Reading Statistics", destination: ReadingPositionHistoryView(libraryId: nil, bookId: nil))
                        NavigationLink("Activity Logs", destination: ActivityList())
                        HStack{}.frame(height: 4)
                    }
                    Group {
                        NavigationLink("Version History", destination: VersionHistoryView())
                        NavigationLink("Support", destination: SupportInfoView())
                        NavigationLink("About calibre Server", destination: ServerCalibreIntroView().frame(maxWidth: 600))
                        NavigationLink("About DSReader", destination: AppInfoView())
                    }
                }.environment(\.defaultMinListRowHeight, 8)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            
            Spacer()
            
            HStack {
                Text("Version \(modelData.resourceFileDictionary?.value(forKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                Text("Build \(modelData.resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1")")
            }
            .font(.caption)
            .foregroundColor(.gray)
            
        }.onAppear() {
            serverList = modelData.calibreServers.map { $0.value }
            sortServerList()
        }
    }
    
    @ViewBuilder
    private func serverRowBuilder(server: CalibreServer) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(server.name)")
                Spacer()
                if modelData.queryServerDSReaderHelper(server: server)?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort ?? 0 > 0 {
                    Image("logo_1024")
                        .resizable()
                        .frame(width: 16, height: 16, alignment: .center)
                }
                if let reachable = modelData.isServerReachable(server: server, isPublic: false) {
                    Image(
                        systemName: reachable ? "flag.circle" : "flag.slash.circle"
                    ).foregroundColor(reachable ? .green : .red)
                }
                
                if let reachable = modelData.isServerReachable(server: server, isPublic: true) {
                    Image(
                        systemName: reachable ? "flag" : "flag.slash"
                    ).foregroundColor(reachable ? .green : .red)
                }
            }
            HStack(spacing: 8) {
                if server.isLocal == false {
                    Text("\(modelData.calibreLibraries.filter{$0.value.server.id == server.id}.count) libraries")
                    
                } else {
                    
                }
            }
            .font(.caption)
            HStack(spacing: 4) {
                Text("Location:")
                if server.isLocal == false {
                    Text(server.username.isEmpty ? "\(server.baseUrl)" : "\(server.username) @ \(server.baseUrl)")
                } else {
                    Text("On Device")
                }
                Spacer()
                
            }
            .font(.caption)

        }
    }
    
    private func sortServerList() {
        serverList.sort {
            if $0.isLocal {
                return false
            }
            if $1.isLocal {
                return true
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.baseUrl < $1.baseUrl
        }
    }
    
    //MARK: Model Funtionalities
    
    private func updateServer(oldServer: CalibreServer, newServer: CalibreServer) {
        do {
            try modelData.updateServerRealm(server: newServer)
        } catch {
            
        }
        modelData.calibreServers.removeValue(forKey: oldServer.id)
        modelData.calibreServers[newServer.id] = newServer
        
        serverList.removeAll { $0.id == oldServer.id }
        serverList.append(newServer)
        sortServerList()
        
        guard oldServer.id != newServer.id else { return }  //minor changes
        
        modelData.calibreServerUpdating = true
        modelData.calibreServerUpdatingStatus = "Updating..."
        
        //if major change occured
        DispatchQueue(label: "data").async {
            let realm = try! Realm(configuration: modelData.realmConf)

            //remove old server from realm
            realm.objects(CalibreServerRealm.self).forEach { serverRealm in
                guard serverRealm.baseUrl == oldServer.baseUrl && serverRealm.username == oldServer.username else {
                    return
                }
                do {
                    try realm.write {
                        realm.delete(serverRealm)
                    }
                } catch {
                    
                }
            }
            
            //update library
            let librariesCached = realm.objects(CalibreLibraryRealm.self)
            librariesCached.forEach { libraryRealm in
                guard libraryRealm.serverUrl == oldServer.baseUrl && libraryRealm.serverUsername == oldServer.username else { return }
                    
                let oldLibrary = CalibreLibrary(
                    server: oldServer,
                    key: libraryRealm.key!,
                    name: libraryRealm.name!,
                    autoUpdate: libraryRealm.autoUpdate,
                    discoverable: libraryRealm.discoverable,
                    lastModified: libraryRealm.lastModified,
                    customColumnInfos: libraryRealm.customColumns.reduce(into: [String: CalibreCustomColumnInfo]()) {
                        $0[$1.label] = CalibreCustomColumnInfo(managedObject: $1)
                    },
                    pluginColumns: {
                        var result = [String: CalibreLibraryPluginColumnInfo]()
                        if let plugin = libraryRealm.pluginDSReaderHelper {
                            result[CalibreLibrary.PLUGIN_DSREADER_HELPER] = CalibreLibraryDSReaderHelper(managedObject: plugin)
                        }
                        if let plugin = libraryRealm.pluginReadingPosition {
                            result[CalibreLibrary.PLUGIN_READING_POSITION] = CalibreLibraryReadingPosition(managedObject: plugin)
                        }
                        if let plugin = libraryRealm.pluginDictionaryViewer {
                            result[CalibreLibrary.PLUGIN_DICTIONARY_VIEWER] = CalibreLibraryDictionaryViewer(managedObject: plugin)
                        }
                        if let plugin = libraryRealm.pluginGoodreadsSync {
                            result[CalibreLibrary.PLUGIN_GOODREADS_SYNC] = CalibreLibraryGoodreadsSync(managedObject: plugin)
                        }
                        if let plugin = libraryRealm.pluginCountPages {
                            result[CalibreLibrary.PLUGIN_COUNT_PAGES] = CalibreLibraryCountPages(managedObject: plugin)
                        }
                        return result
                    }()
                )
                
                
                let newLibrary = CalibreLibrary(
                    server: newServer,
                    key: oldLibrary.key,
                    name: oldLibrary.name,
                    autoUpdate: oldLibrary.autoUpdate,
                    discoverable: oldLibrary.discoverable,
                    lastModified: oldLibrary.lastModified,
                    customColumnInfos: oldLibrary.customColumnInfos,
                    pluginColumns: oldLibrary.pluginColumns)
                
                do {
                    try realm.write {
                        realm.delete(libraryRealm)
                    }
                } catch {
                    
                }
                
                DispatchQueue.main.sync {
                    try? modelData.updateLibraryRealm(library: newLibrary, realm: modelData.realm)
                    modelData.calibreLibraries.removeValue(forKey: oldLibrary.id)
                    modelData.calibreLibraries[newLibrary.id] = newLibrary
                }
                
            }
            
            //update books
            let booksCached = realm.objects(CalibreBookRealm.self)
            do {
                try realm.write {
                    booksCached.forEach { oldBookRealm in
                        guard oldBookRealm.serverUrl == oldServer.baseUrl && oldBookRealm.serverUsername == oldServer.username else { return }
                        let newBookRealm = CalibreBookRealm(value: oldBookRealm)
                        newBookRealm.serverUrl = newServer.baseUrl
                        newBookRealm.serverUsername = newServer.username
                        
                        realm.delete(oldBookRealm)
                        realm.add(newBookRealm, update: .all)
                    }
                }
            } catch {
                
            }
            
            DispatchQueue.main.sync {
                //reload shelf
                modelData.realm.refresh()

                modelData.booksInShelf.removeAll(keepingCapacity: true)
                modelData.populateBookShelf()
                
                //reload book list
                modelData.calibreServerUpdating = false
                modelData.calibreServerUpdatingStatus = "Finished"
                
                modelData.currentCalibreServerId = newServer.id
            }
        }
    }
    
    private func deleteServer() {
        let server = serverList.remove(at: serverListDeleteIndex)
        let isSuccess = modelData.removeServer(serverId: server.id)
        if !isSuccess {
            alertItem = AlertItem(id: "DelServerFailed")
        }
    }
    
}

struct SettingsView_Previews: PreviewProvider {
    static private var modelData = ModelData()

    static var previews: some View {
        SettingsView()
            .environmentObject(modelData)
    }
}
