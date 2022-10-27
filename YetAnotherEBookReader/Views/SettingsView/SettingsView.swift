//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI
import Combine
import RealmSwift

struct SettingsView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var selectedServer: String? = nil
    
    @State private var addServerActive = false
    @State private var alertItem: AlertItem?

    @State private var serverList = [CalibreServer]()
    @State private var serverListDelete: CalibreServer? = nil
    @State private var updater = 0

    @State private var removeServerCancellable: AnyCancellable?
    
    var body: some View {
        Form {
            Section(header: HStack {
                Text("Servers")
                Spacer()
                if let serverListDelete = serverListDelete {
                    Text("Removing \(serverListDelete.name)")
                    ProgressView().progressViewStyle(CircularProgressViewStyle())
                } else if modelData.calibreServerInfoStaging.allSatisfy{$1.probing == false} == false {
                    Text("Refreshing")
                    ProgressView().progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text(modelData.calibreServerUpdatingStatus ?? "")
                    ProgressView().progressViewStyle(CircularProgressViewStyle()).hidden()
                }
            }) {
                NavigationLink(
                    destination: AddModServerView(
                        server: Binding<CalibreServer>(get: {
                            .init(name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
                        }, set: { _ in
                            updateServerList()
                        }),
                        isActive: $addServerActive
                    )
                    .navigationTitle("Add Server"),
                    isActive: $addServerActive
                ) {
                    Text("Connect to a new server")
                }
                
                ForEach(serverList, id: \.self) { server in
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
                    guard let index = indexSet.first, index < serverList.count else { return }
                    serverListDelete = serverList.remove(at: index)
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
                            secondaryButton: .cancel{
                                serverListDelete = nil
                            }
                        )
                    }
                    return Alert(title: Text("Error"), message: Text(item.id + "\n" + (item.msg ?? "")), dismissButton: .cancel() {
                        item.action?()
                    })
                }
            }
            .disabled(serverListDelete != nil)
            
            Section(header: Text("Options")) {
                NavigationLink("Formats & Readers", destination: ReaderOptionsView())
                NavigationLink("Reading Statistics", destination: ReadingPositionHistoryView(presenting: Binding<Bool>(get: { false }, set: { _ in }), library: nil, bookId: nil))
                NavigationLink("Activity Logs", destination: ActivityList(presenting: Binding<Bool>(get: { false }, set: { _ in } )))
            }
            
            Section(
                header: Text("Support"),
                footer: HStack {
                    Spacer()
                    Text("Version \(modelData.resourceFileDictionary?.value(forKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                    Text("Build \(modelData.resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1")")
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.gray)
            ) {
                NavigationLink("Version History", destination: VersionHistoryView())
                NavigationLink("Support", destination: SupportInfoView())
                NavigationLink("About calibre Server", destination: ServerCalibreIntroView().frame(maxWidth: 600))
                NavigationLink("About DSReader", destination: AppInfoView())
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem {
                Button(action:{
                    modelData.probeServersReachability(with: [], updateLibrary: true)
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .onAppear() {
            updateServerList()
        }
        .onChange(of: serverListDelete, perform: { value in
            updateServerList()
        })
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if server.isLocal == false {
                        Text("\(modelData.calibreLibraries.filter{$0.value.server.id == server.id}.count) libraries")
                    } else {
                        
                    }
                    
                    HStack(spacing: 4) {
                        Text("Location:")
                        if server.isLocal == false {
                            Text(server.username.isEmpty ? "\(server.baseUrl)" : "\(server.username) @ \(server.baseUrl)")
                        } else {
                            Text("On Device")
                        }
                    }
                }
                
                Spacer()
                
                if modelData.librarySyncStatus.filter { $0.value.isSync && modelData.calibreLibraries[$0.key]?.server.id == server.id }.count > 0 {
                    Text("\(modelData.librarySyncStatus.filter { $0.value.isSync && modelData.calibreLibraries[$0.key]?.server.id == server.id }.count) processing")
                } else if let serverInfo = modelData.getServerInfo(server: server) {
                    if serverInfo.reachable {
                        Text("Server has \(serverInfo.libraryMap.count) libraries")
                    } else {
                        Text("\(serverInfo.errorMsg)")
                            .foregroundColor(.red)
                    }
                }
            }
            .font(.caption)
        }
    }
    
    private func updateServerList() {
        serverList = modelData.calibreServers
            .filter { $1.isLocal == false && $1.id != serverListDelete?.id}
            .map { $0.value }
        sortServerList()
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
            if $0.baseUrl != $1.baseUrl {
                return $0.baseUrl < $1.baseUrl
            }
            return $0.username < $1.username
        }
    }
    
    //MARK: Model Funtionalities
    
    private func updateServer(oldServer: CalibreServer, newServer: CalibreServer) {
        if oldServer.id == newServer.id {
            //minor changes only
            modelData.calibreServers[newServer.id] = newServer
            try? modelData.updateServerRealm(server: newServer)
            if let index = serverList.firstIndex(where: {$0.id == newServer.id}) {
                serverList[index] = newServer
            }

            modelData.calibreServerUpdatingStatus = "Updated"
            return
        }
        
        serverListDelete = oldServer        //staging
        print("\(#function) staging finished \(oldServer.id) -> \(newServer.id)")

        modelData.calibreServerUpdating = true
        modelData.calibreServerUpdatingStatus = "Updating..."
        
        let newServerLibraries = modelData.calibreLibraries.filter { $1.server.id == oldServer.id }.map { id, library -> CalibreLibrary in
            var newLibrary = library
            newLibrary.server = newServer
            if var syncStat = modelData.librarySyncStatus[library.id] {
                syncStat.library = newLibrary
                modelData.librarySyncStatus[newLibrary.id] = syncStat
            }
            return newLibrary
        }
        
        modelData.addServer(server: newServer, libraries: newServerLibraries)
        
        selectedServer = nil
        print("\(#function) addServer finished")
        
        DispatchQueue(label: "data").async {
            let realm = try! Realm(configuration: modelData.realmConf)

            //update books
            let booksCached = realm.objects(CalibreBookRealm.self)
                .filter("serverUrl == %@ AND serverUsername == %@", oldServer.baseUrl, oldServer.username)
            let booksCount = booksCached.count
            var booksProgress = 0
            do {
                var batch: [CalibreBookRealm] = booksCached.prefix(256).map { $0 }
                while batch.count > 0 {
                    booksProgress += batch.count
                    print("\(#function) update books \(batch.count) / \(booksProgress) / \(booksCount)")
                    DispatchQueue.main.async {
                        modelData.calibreServerUpdatingStatus = "Updating... \(booksProgress)/\(booksCount)"
                    }
                    
                    try realm.write {
                        batch.forEach { oldBookRealm in
                            let newBookRealm = CalibreBookRealm(value: oldBookRealm)
                            newBookRealm.serverUrl = newServer.baseUrl
                            newBookRealm.serverUsername = newServer.username
                            newBookRealm.updatePrimaryKey()
                            realm.delete(oldBookRealm)
                            realm.add(newBookRealm, update: .all)
                        }
                    }
                    batch = booksCached.prefix(256).map { $0 }
                }
            } catch {
                print("\(#function) update books error=\(error)")
            }
            print("\(#function) update books finished")

            DispatchQueue.main.async {
                modelData.calibreServerUpdatingStatus = "Cleanup up..."
            }
            let _ = modelData.removeServer(serverId: oldServer.id, realm: realm)
            
            print("\(#function) removeServer finished")

            DispatchQueue.main.async {
                //reload shelf
                modelData.realm.refresh()

                modelData.booksInShelf.removeAll(keepingCapacity: true)
                modelData.populateBookShelf()
                
                modelData.calibreServerUpdating = false
                modelData.calibreServerUpdatingStatus = "Finished"
                
                serverListDelete = nil      //will trigger updateServerList

                modelData.probeServersReachability(with: [newServer.id])
            }
        }
    }
    
    private func deleteServer() {
        guard let server = serverListDelete else { return }
        
        modelData.calibreServiceCancellable?.cancel()
        modelData.dshelperRefreshCancellable?.cancel()
        modelData.syncLibrariesIncrementalCancellable?.cancel()
        
        removeServerCancellable = [server].publisher
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
            .sink { output in
                guard let realm = try? Realm(configuration: modelData.realmConf) else { return }
                let isSuccess = modelData.removeServer(serverId: server.id, realm: realm)
                if !isSuccess {
                    alertItem = AlertItem(id: "DelServerFailed")
                }
                serverListDelete = nil
                NotificationCenter.default.post(.init(name: .YABR_RecentShelfBooksRefreshed))
                NotificationCenter.default.post(.init(name: .YABR_DiscoverShelfBooksRefreshed))
            }
    }
    
}

struct SettingsView_Previews: PreviewProvider {
    static private var modelData = ModelData()

    static var previews: some View {
        NavigationView {
            SettingsView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(modelData)
    }
}
