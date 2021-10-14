//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/31.
//

import SwiftUI
import OSLog

struct ServerView: View {
    @EnvironmentObject var modelData: ModelData
    
    // bindings for server editing
    @State private var calibreServerName = ""
    @State private var calibreServerUrl = ""
    @State private var calibreServerUrlPublic = ""
    @State private var calibreServerSetPublicAddress = false
    @State private var calibreServerNeedAuth = false
    @State private var calibreUsername = ""
    @State private var calibrePassword = ""

    // bindings for library options
    @State private var enableStoreReadingPosition = false
    @State private var storeReadingPositionColumnName = ""
    @State private var isDefaultReadingPosition = false
    
    @State private var enableGoodreadsSync = false
    @State private var goodreadsSyncProfileName = ""
    @State private var isDefaultGoodreadsSync = false
    
    //
    @State private var calibreServerEditing = false
    
    @State private var dataAction = ""
    @State private var dataLoading = false
    
    @State private var serverCalibreInfoPresenting = false
    
    @State private var localLibraryImportBooksPicked = [URL]()
    @State private var localLibraryImportPresenting = false
    
    @State private var updater = 0
    
    var defaultLog = Logger()
    
    @State private var alertItem: AlertItem?
    @State private var alertContent: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {  //Server & Library Settings
                HStack {
                    Spacer()
                    Button(action:{
                        serverCalibreInfoPresenting = true
                    }) {
                        Text("What's calibre server?")
                            .font(.caption)
                    }
                }
                .sheet(isPresented: $serverCalibreInfoPresenting, onDismiss: { serverCalibreInfoPresenting = false }, content: {
                    ServerCalibreIntroView()
                        .frame(maxWidth: 600)
                })
                HStack {
                    Picker("Switch Server", selection: $modelData.currentCalibreServerId) {
                        ForEach(modelData.calibreServers.values.map { $0.id }.sorted { $0 < $1 }, id: \.self) { serverId in
                            Text(serverId)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(calibreServerEditing)
                    
                    Spacer()
                    
                    if calibreServerEditing {
                        Button(action:{
                            if dataAction == "Add" {
                                addServerConfirmButtonAction()
                            }
                            if dataAction == "Mod" {
                                modServerConfirmButtonAction()
                            }
                        }) {
                            Image(systemName: "checkmark")
                        }
                        Button(action:{ calibreServerEditing = false }) {
                            Image(systemName: "xmark")
                        }
                    } else {
                        Button(action:{
                            calibreServerEditing = true
                            dataAction = "Add"
                        }) {
                            Text("Add")
                        }
                        
                        Button(action:{
                            alertItem = AlertItem(id: "DelServer")
                        }) {
                            Image(systemName: "minus")
                        }.disabled(!canDeleteCurrentServer())
                        
                        Button(action:{
                            guard let server = modelData.currentCalibreServer else { return }
                            calibreServerName = server.name
                            calibreServerUrl = server.baseUrl
                            calibreUsername = server.username
                            calibrePassword = server.password
                            calibreServerUrlPublic = server.publicUrl
                            calibreServerSetPublicAddress = !calibreServerUrlPublic.isEmpty
                            calibreServerNeedAuth = !calibreUsername.isEmpty
                            calibreServerEditing = true
                            dataAction = "Mod"
                        }) {
                            Image(systemName: "square.and.pencil")
                        }.disabled(!canDeleteCurrentServer())
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    if calibreServerEditing {
                        HStack {
                            Image(systemName: "at")
                            TextField("Name Your Server", text: $calibreServerName)
                                .border(Color(UIColor.separator))
                        }
                        HStack {
                            Image(systemName: "server.rack")
                            TextField("Internal Server Address", text: $calibreServerUrl)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))
                        }
                        
                        VStack {
                            Toggle("Set a Separate Public Address?", isOn: $calibreServerSetPublicAddress)
                            if calibreServerSetPublicAddress {
                                HStack {
                                    Image(systemName: "cloud")
                                    TextField("Internet Server Address", text: $calibreServerUrlPublic)
                                        .keyboardType(.URL)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .border(Color(UIColor.separator))
                                }
                                HStack {
                                    Text("It's highly recommended to enable HTTPS and user authentication before exposing server to Internet.")
                                        .fixedSize(horizontal: false, vertical: true)
                                        .font(.caption)
                                    Spacer()
                                    Button(action:{
                                        
                                    }) {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            }
                        }
                        
                        Toggle("Need Auth?", isOn: $calibreServerNeedAuth)
                        
                        if calibreServerNeedAuth {
                            HStack {
                                Text("Username:")
                                TextField("Username", text: $calibreUsername)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .border(Color(UIColor.separator))
                            }
                            HStack {
                                Text("Password:")
                                SecureField("Password", text: $calibrePassword)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .border(Color(UIColor.separator))
                            }
                        }
                        
                        HStack {
                            if dataLoading {
                                Text("Connecting...")
                            }
                            if modelData.calibreServerUpdating {
                                Text(modelData.calibreServerUpdatingStatus ?? "")
                            }
                            
                            Spacer()
                            
                        }
                    } else if let server = modelData.currentCalibreServer {
                        HStack {
                            Text("Current Server: \(server.name)")
                            
                            Spacer()
                            
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
                        if server.isLocal == false {
                            HStack(alignment: .center, spacing: 8) {
                                Text(modelData.calibreServerUpdatingStatus ?? "")
                                
                                Spacer()
                                
                                Text("\(modelData.currentCalibreServerLibraries.count) Library(s) in Server")
                                
                                Button(action: {
                                    guard let server = modelData.currentCalibreServer else { return }
                                    dataAction = "Sync"
                                    dataLoading = true  //ready for consuming results
                                    modelData.calibreServerService.getServerLibraries(server: server)
                                }) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                    }
                }
                .onChange(of: calibreServerEditing) { newState in
                    if newState == false {
                        resetEditingFields()
                    }
                }
                .onChange(of: modelData.calibreServerUpdatingStatus) { newStatus in
                    //handle sync library action
                    guard dataLoading else { return }   //triggered by other initiator
                    guard let serverInfo = modelData.calibreServerInfo else { return }
                    
                    if dataAction == "Sync" {
                        if newStatus == "Success" {
                            modelData.updateServerLibraryInfo(serverInfo: serverInfo)
                            dataLoading = false
                        } else {
                            self.alertItem = AlertItem(id: "Sync Error", msg: serverInfo.errorMsg, action: {
                                dataLoading = false
                            })
                        }
                    }
                    if dataAction == "Add" {
                        if newStatus == "Success" {
                            dataLoading = false

                            var content = "Library List:"
                            serverInfo.libraryMap
                                .sorted { $0.1 < $1.1 }
                                .forEach { content += "\n\($0.1)" }
                            
                            
                            alertItem = AlertItem(id: "AddServer", msg: content)
                        } else {
                            self.alertItem = AlertItem(id: "Add Error", msg: serverInfo.errorMsg, action: {
                                dataLoading = false
                            })
                        }
                    }
                    if dataAction == "Mod" {
                        if newStatus == "Success" {
                            dataLoading = false
                            
                            var content = "Library List:"
                            serverInfo.libraryMap
                                .sorted { $0.1 < $1.1 }
                                .forEach { content += "\n\($0.1)" }
                            
                            alertItem = AlertItem(id: "ModServer", msg: content)
                        } else {
                            self.alertItem = AlertItem(id: "Mod Error", msg: serverInfo.errorMsg, action: {
                                dataLoading = false
                            })
                        }
                    }
                    
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Switch Library", selection: $modelData.currentCalibreLibraryId) {
                            ForEach(modelData.currentCalibreServerLibraries.sorted(by: { $0.name < $1.name })) { library in
                                Text(library.name).tag(library.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: modelData.currentCalibreLibraryId, perform: { value in
                            guard let library = modelData.currentCalibreLibrary else { return }
                            
                            enableStoreReadingPosition = library.readPosColumnName != nil
                            storeReadingPositionColumnName = library.readPosColumnName ?? library.readPosColumnNameDefault
                            
                            enableGoodreadsSync = library.goodreadsSyncProfileName != nil
                            goodreadsSyncProfileName = library.goodreadsSyncProfileName ?? library.goodreadsSyncProfileNameDefault
                        })
                        
                        Spacer()
                        
                        if modelData.currentCalibreServer?.isLocal == true {
                            Button(action: {
                                localLibraryImportBooksPicked.removeAll()
                                localLibraryImportPresenting = true
                            }) {
                                Text("Import")
                            }.sheet(isPresented: $localLibraryImportPresenting, onDismiss: {
                                localLibraryImportPresenting = false
                            }) {
                                BookImportPicker(bookURLs: $localLibraryImportBooksPicked)
                            }.onChange(of: localLibraryImportBooksPicked) { urls in
                                guard urls.isEmpty == false else { return }
                                
                                let imported = urls.filter {
                                    modelData.onOpenURL(url: $0)
                                }
                                
                                modelData.calibreServerUpdatingStatus = "\(urls.count) selected, \(imported.count) imported"
                                
                                modelData.populateLocalLibraryBooks()

                            }
                        }
                        
                        Button(action: {
                            alertItem = AlertItem(id: "DelLibrary")
                        }) {
                            Image(systemName: "trash")
                        }
                    }
                    
                    Text("Current Library: \(modelData.currentCalibreLibrary?.name ?? "No Library Selected")")
                    HStack(alignment: .center, spacing: 8) {
                        Text(modelData.calibreServerUpdatingStatus ?? "")
                        
                        Spacer()
                        
                        if modelData.calibreServerLibraryUpdating {
                            Text("Refreshing Metadata \(modelData.calibreServerLibraryUpdatingProgress)/\(modelData.calibreServerLibraryUpdatingTotal), please wait a moment...")
                        } else {
                            Text("\(modelData.calibreServerLibraryBooks.count) Book(s) in Library")
                        }
                        
                        Button(action: {
                            modelData.syncLibrary(alertDelegate: self)
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }.onChange(of: modelData.calibreServerLibraryUpdatingProgress) {_ in
                        updater += 1
                    }
                }
                
                if modelData.currentCalibreServer?.isLocal == false {
                    VStack(alignment:.leading, spacing: 4) {
                    Divider()
                    
                    Text("Advanced Library Settings")
                    Toggle("Store Reading Position in Custom Column", isOn: $enableStoreReadingPosition)
                        .onChange(of: enableStoreReadingPosition) { enabled in
                            modelData.updateStoreReadingPosition(enabled: enabled, value: storeReadingPositionColumnName)
                            if enabled {
                                
                            }
                        }
                    Text("Therefore reading positions can be synced between devices.")
                        .font(.caption)
                    if enableStoreReadingPosition {
                        HStack {
                            Text("Column:").padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0))
                            TextField("#name", text: $storeReadingPositionColumnName, onCommit:  {
                                modelData.updateStoreReadingPosition(enabled: true, value: storeReadingPositionColumnName)
                            })
                            .keyboardType(.alphabet)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .border(Color(UIColor.separator))
                        }
                        Text("Please add a custom column of type \"Long text\" on calibre server.\nIf there are multiple users, it's better to add a unique column for each user.")
                            .font(.caption)
                        if modelData.currentCalibreServer?.username.isEmpty ?? false {
                            Text("Also note that server defaults to read-only mode when user authentication is not required, so please allow un-authenticated connection to make changes (\"Advanced\" tab in \"Sharing over the net\")")
                            .font(.caption)
                        }
                        HStack {
                            Spacer()
                            Button(action:{
                                isDefaultReadingPosition = true
                            }) {
                                Text("Set as Server-wide Default")
                            }
                            if isDefaultReadingPosition {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: "checkmark")
                                    .hidden()
                            }
                        }
                    }
                    
                    Toggle("Enable Goodreads Sync", isOn: $enableGoodreadsSync)
                        .onChange(of: enableGoodreadsSync, perform: { value in
                            modelData.updateGoodreadsSyncProfileName(enabled: value, value: goodreadsSyncProfileName)
                        })
                    if enableGoodreadsSync {
                        HStack {
                            Text("Profile:").padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0))
                            TextField("Name", text: $goodreadsSyncProfileName, onCommit:  {
                                modelData.updateGoodreadsSyncProfileName(enabled: true, value: goodreadsSyncProfileName)
                            })
                            .keyboardType(.alphabet)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .border(Color(UIColor.separator))
                        }
                        Text("This is a Work-in-Progress, please stay tuned!")
                            .font(.caption)
                        
                        HStack {
                            Spacer()
                            Button(action:{
                                isDefaultGoodreadsSync = true
                            }) {
                                Text("Set as Server-wide Default")
                            }
                            if isDefaultGoodreadsSync {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: "checkmark")
                                    .hidden()
                            }
                        }
                    }
                }
                }
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .disabled(modelData.calibreServerUpdating || modelData.calibreServerLibraryUpdating || dataLoading)
            
            Spacer()
        }
        .onAppear() {
//            calibreServerId = modelData.currentCalibreServerId
//            calibreServerLibraryId = modelData.currentCalibreLibraryId
            
            if let library = modelData.currentCalibreLibrary {
                enableStoreReadingPosition = library.readPosColumnName != nil
                storeReadingPositionColumnName = library.readPosColumnName ?? library.readPosColumnNameDefault
                
                enableGoodreadsSync = library.goodreadsSyncProfileName != nil
                goodreadsSyncProfileName = library.goodreadsSyncProfileName ?? library.goodreadsSyncProfileNameDefault
                print("StoreReadingPosition \(enableStoreReadingPosition) \(storeReadingPositionColumnName) \(library)")
            }
        }
        .navigationBarHidden(false)
        .statusBar(hidden: false)
        .alert(item: $alertItem) { item in
            if item.id == "AddServer" {
                return Alert(title: Text("Add Server"),
                             message: Text(item.msg!),
                             primaryButton: .default(Text("Confirm")
                             ) {
                                addServerConfirmed()
                             },
                             secondaryButton: .cancel())
            }
            if item.id == "AddServerExists" {
                return Alert(title: Text("Add Server"), message: Text("Duplicate"), dismissButton: .cancel())
            }
            if item.id == "DelServer" {
                return Alert(
                    title: Text("Remove Server"),
                    message: Text("Will Remove Cached Libraries and Books from Reader, Everything on Server will Stay Intact"),
                    primaryButton: .destructive(Text("Confirm")) {
                        delServerConfirmed()
                    },
                    secondaryButton: .cancel()
                )
            }
            if item.id == "DelLibrary" {
                return Alert(
                    title: Text("Remove Library"),
                    message: Text("Will Remove Cached Book List and Book Files from Reader, Everything on Server will Stay Intact"),
                    primaryButton: .destructive(Text("Confirm")) {
                        delLibraryConfirmed()
                    },
                    secondaryButton: .cancel()
                )
            }
            if item.id == "ModServer" {
                return Alert(title: Text("Mod Server"),
                             message: Text(alertContent),
                             primaryButton: .default(Text("Confirm")
                             ) {
                                modServerConfirmed()
                             },
                             secondaryButton: .cancel())
            }
            return Alert(title: Text("Error"), message: Text(item.id + "\n" + (item.msg ?? "")), dismissButton: .cancel() {
                item.action?()
            })
        }
    }
    
    private func canDeleteCurrentServer() -> Bool {
        guard let server = modelData.currentCalibreServer else {
            return false
        }
        return !server.isLocal
    }
    
    private func addServerConfirmButtonAction() {
        let calibreServer = CalibreServer(
            name: calibreServerName, baseUrl: calibreServerUrl, publicUrl: calibreServerUrlPublic, username: calibreUsername, password: calibrePassword)
        if modelData.calibreServers[calibreServer.id] != nil {
            alertItem = AlertItem(id: "AddServerExists")
            return
        }

        dataLoading = true
        modelData.calibreServerService.getServerLibraries(server: calibreServer)
    }
    
    private func addServerConfirmed() {
        guard let serverInfo = modelData.calibreServerInfo else { return }
        
        var server = serverInfo.server
        server.defaultLibrary = serverInfo.defaultLibrary
        server.lastLibrary = serverInfo.defaultLibrary
        
        let libraries = serverInfo.libraryMap
            .sorted { $0.key < $1.key }
            .map { CalibreLibrary(server: serverInfo.server, key: $0, name: $1) }
        
        modelData.addServer(server: server, libraries: libraries)
        modelData.currentCalibreServerId = server.id
        if let defaultLibraryId = libraries.filter({
            $0.name == $0.server.defaultLibrary
        }).first?.id {
            modelData.currentCalibreLibraryId = defaultLibraryId
        }
        modelData.probeServersReachability(with: [server.id])
        
        calibreServerEditing = false
    }
    
    private func modServerConfirmButtonAction() {
        let newServer = CalibreServer(
            name: calibreServerName, baseUrl: calibreServerUrl, publicUrl: calibreServerUrlPublic, username: calibreUsername, password: calibrePassword)
        guard let oldServer = modelData.currentCalibreServer else {
            alertItem = AlertItem(id: "ModServerNotExist")  //shouldn't reach here
            return
        }
        
        if newServer.id == oldServer.id {
            //minor changes
            modelData.updateServer(oldServer: oldServer, newServer: newServer)
        } else {
            dataLoading = true
            modelData.calibreServerService.getServerLibraries(server: newServer)
        }
    }
    
    private func modServerConfirmed() {
        guard let oldServer = modelData.currentCalibreServer,
              let serverInfo = modelData.calibreServerInfo else {
            alertItem = AlertItem(id: "Error", msg: "Unexpected Error")
            return
            
        }
        
        var newServer = serverInfo.server
        newServer.defaultLibrary = serverInfo.defaultLibrary
        newServer.lastLibrary = oldServer.lastLibrary
        
        modelData.updateServer(oldServer: oldServer, newServer: newServer)
        
        modelData.probeServersReachability(with: [newServer.id])

        calibreServerEditing = false
    }
    
    private func delServerConfirmed() {
        let isSuccess = modelData.removeServer(serverId: modelData.currentCalibreServerId)
        if !isSuccess {
            alertItem = AlertItem(id: "DelServerFailed")
        }
    }
    
    private func delLibraryConfirmed() {
        let isSuccess = modelData.removeLibrary(libraryId: modelData.currentCalibreLibraryId)
        modelData.filteredBookList.removeAll()
        modelData.calibreServerLibraryBooks.removeAll()
        
        if !isSuccess {
            alertItem = AlertItem(id: "DelLibraryFailed")
        }
    }
    
    private func resetEditingFields() {
        calibreServerName.removeAll()
        calibreServerUrl.removeAll()
        calibreServerUrlPublic.removeAll()
        calibreServerSetPublicAddress = false
        calibreServerNeedAuth = false
        calibreUsername.removeAll()
        calibrePassword.removeAll()
    }
}

extension ServerView : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

struct ServerView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        ServerView()
            .environmentObject(modelData)
    }
}
