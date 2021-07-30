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
    
//    @State private var calibreServerId = ""
//    @State private var calibreServerLibraryId = "Undetermined"
    
    @State private var calibreServerName = ""
    @State private var calibreServerUrl = ""
    @State private var calibreServerUrlPublic = ""
    @State private var calibreServerSetPublicAddress = false
    @State private var calibreServerNeedAuth = false
    @State private var calibreUsername = ""
    @State private var calibrePassword = ""
    @State private var calibreDefaultLibrary = ""
    @State private var calibreServerLibrariesEdit = [CalibreLibrary]()
    
    @State private var enableStoreReadingPosition = false
    @State private var storeReadingPositionColumnName = ""
    @State private var isDefaultReadingPosition = false
    
    @State private var enableGoodreadsSync = false
    @State private var goodreadsSyncProfileName = ""
    @State private var isDefaultGoodreadsSync = false
    
    @State private var calibreServerEditing = false
    
    @State private var dataLoading = false
    
    @State private var updater = 0
    
    var defaultLog = Logger()
    
    struct AlertItem : Identifiable {
        var id: String
        var action: (() -> Void)?
    }
    @State private var alertItem: AlertItem?
    @State private var alertContent: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {  //Server & Library Settings
                HStack {
                    Picker("Switch Server", selection: $modelData.currentCalibreServerId) {
                        ForEach(modelData.calibreServers.values.map { $0.id }.sorted { $0 < $1 }, id: \.self) { serverId in
                            Text(serverId)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Spacer()
                    
                    Button(action:{
                        calibreServerEditing = true
                    }) {
                        Image(systemName: "plus")
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
                        calibreDefaultLibrary = server.defaultLibrary
                        calibreServerLibrariesEdit = modelData.currentCalibreServerLibraries
                        calibreServerEditing = true
                    }) {
                        Image(systemName: "square.and.pencil")
                    }.disabled(!canDeleteCurrentServer())
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
                            Spacer()
                            Button(action:{ calibreServerEditing = false }) {
                                Image(systemName: "xmark")
                            }
                            Button(action:{
                                if calibreServerLibrariesEdit.isEmpty && calibreDefaultLibrary.isEmpty {
                                    addServerConfirmButtonAction()
                                } else {
                                    modServerConfirmButtonAction()
                                }
                            }) {
                                Image(systemName: "checkmark")
                            }
                        }
                        
                        
                    } else {
                        Text("Current Server: \(modelData.currentCalibreServerId)")
                        
                        HStack(alignment: .center, spacing: 8) {
                            Spacer()
                            
                            Text("\(modelData.currentCalibreServerLibraries.count) Library(s) in Server")
                            
                            Button(action: {
                                guard let server = modelData.currentCalibreServer else { return }
                                let ret = startLoadServerLibraries(
                                    calibreServer: server,
                                    parse: handleLibraryInfo(jsonData:)
                                ) {
                                    modelData.updateServerLibraryInfo(
                                        serverId: modelData.currentCalibreServerId,
                                        libraries: calibreServerLibrariesEdit,
                                        defaultLibrary: calibreDefaultLibrary
                                    )
                                }
                                if ret != 0 {
                                    //TODO
                                }
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
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
                        
                        Button(action: {
                            alertItem = AlertItem(id: "DelLibrary")
                        }) {
                            Image(systemName: "trash")
                        }
                    }
                    
                    Text("Current Library: \(modelData.currentCalibreLibrary?.name ?? "No Library Selected")")
                    HStack(alignment: .center, spacing: 8) {
                        Spacer()
                        
                        if modelData.calibreServerLibraryUpdating {
                            Text("Loading Books \(modelData.calibreServerLibraryUpdatingProgress)/\(modelData.calibreServerLibraryUpdatingTotal), please wait a moment...")
                        } else {
                            Text("\(modelData.calibreServerLibraryBooks.count) Book(s) in Library")
                        }
                        
                        Button(action: { syncLibrary() }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }.onChange(of: modelData.calibreServerLibraryUpdatingProgress) {_ in
                        updater += 1
                    }
                }
                
                VStack(alignment:.leading, spacing: 4) {
                    Divider()
                    
                    Text("Library Settings")
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
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .disabled(dataLoading)
            .disabled(modelData.calibreServerLibraryUpdating)
            
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
                             message: Text(alertContent),
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
            return Alert(title: Text("Error"), message: Text(item.id), dismissButton: .cancel() {
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
    
    private func syncLibrary() {
        guard let server = modelData.currentCalibreServer,
              let library = modelData.currentCalibreLibrary,
              let libraryKeyEncoded = library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let endpointUrl = URL(string: server.serverUrl + "/cdb/cmd/list/0?library_id=" + libraryKeyEncoded)
              else {
            return
        }
        
        let json:[Any] = [["title", "authors", "formats", "rating", "series", "identifiers"], "", "", "", -1]
        
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.alertItem = AlertItem(id: error.localizedDescription, action: {
                    dataLoading = false
                })
                defaultLog.warning("error: \(error.localizedDescription)")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                defaultLog.warning("not httpResponse: \(response.debugDescription)")
                self.alertItem = AlertItem(id: response?.description ?? "nil reponse", action: {
                    dataLoading = false
                })
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data {
                DispatchQueue(label: "data").async {
                    //self.webView.loadHTMLString(string, baseURL: url)
                    //result = string
                    modelData.handleLibraryBooks(json: data) { isSuccess in
                        dataLoading = false
                        
                        if !isSuccess {
                            self.alertItem = AlertItem(id: "Failed to parse calibre server response.")
                        }
                    }
                }
            }
        }
        
        dataLoading = true
        task.resume()
    }
    
    private func handleClientError(_ error: Error) {
        
    }
    
    private func updateLibrary() {
        
    }
    
    func startLoadServerLibraries(calibreServer: CalibreServer, parse: @escaping (_ jsonData: Data) -> Void, complete: () -> Void) -> Int {
        if dataLoading {
            return 1
        }
        guard let url = URL(string: calibreServer.serverUrl + "/ajax/library-info") else {
            return 2
        }
        if calibreServerName.isEmpty {
            calibreServerName = "My Server on \(url.host ?? "unknown host")"
        }
        if calibreServer.username.count > 0 && calibreServer.password.count > 0 {
            var authMethod = NSURLAuthenticationMethodDefault
            if url.scheme == "http" {
                authMethod = NSURLAuthenticationMethodHTTPDigest
            }
            if url.scheme == "https" {
                authMethod = NSURLAuthenticationMethodHTTPBasic
            }
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            let userCredential = URLCredential(user: calibreServer.username,
                                               password: calibreServer.password,
                                               persistence: .forSession)
            URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print(error.localizedDescription)
                self.alertItem = AlertItem(id: error.localizedDescription, action: {
                    dataLoading = false
                })
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                self.alertItem = AlertItem(id: response?.description ?? "nil reponse", action: {
                    dataLoading = false
                })
                return
            }
            guard httpResponse.statusCode != 401 else {
                self.alertItem = AlertItem(id: "Need to Provide User Authentication to Access Server", action: {
                    dataLoading = false
                })
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                self.alertItem = AlertItem(id: httpResponse.description, action: {
                    dataLoading = false
                })
                return
            }
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data {
                DispatchQueue.main.async {
                    parse(data)
                    dataLoading = false
                }
            }
        }
        
        dataLoading = true
        
        if calibreServer.username.count > 0 && calibreServer.password.count > 0 {
            var authMethod = NSURLAuthenticationMethodDefault
            if url.scheme == "http" {
                authMethod = NSURLAuthenticationMethodHTTPDigest
            }
            if url.scheme == "https" {
                authMethod = NSURLAuthenticationMethodHTTPBasic
            }
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            if let credentials = URLCredentialStorage.shared.credentials(for: protectionSpace) {
                if let credential = credentials.filter({ $0.key == calibreServer.username }).first?.value {
                    URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: task)
                }
            }
            
        }
        
        
        task.resume()
        return 0
    }
    
    func handleLibraryInfo(jsonData: Data) {
        var calibreServer = CalibreServer(name: calibreServerName, baseUrl: calibreServerUrl, publicUrl: calibreServerUrlPublic, username: calibreUsername, password: calibrePassword)
        
        if let libraryInfo = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? NSDictionary {
            defaultLog.info("libraryInfo: \(libraryInfo)")
            
            if let libraryMap = libraryInfo["library_map"] as? [String: String] {
                if let defaultLibrary = libraryInfo["default_library"] as? String {
                    calibreServer.defaultLibrary = defaultLibrary
                    calibreDefaultLibrary = defaultLibrary
                }
                if calibreServer.lastLibrary.isEmpty {
                    calibreServer.lastLibrary = calibreServer.defaultLibrary
                }
                calibreServerLibrariesEdit.removeAll()
                libraryMap.sorted(by: { $0.key < $1.key }).forEach { (key, value) in
                    calibreServerLibrariesEdit.append(CalibreLibrary(server: calibreServer, key: key, name: value))
                }
            }
            
        } else {
            
        }
    }
    
    private func addServerConfirmButtonAction() {
        let calibreServer = CalibreServer(
            name: calibreServerName, baseUrl: calibreServerUrl, publicUrl: calibreServerUrlPublic, username: calibreUsername, password: calibrePassword)
        if modelData.calibreServers[calibreServer.id] != nil {
            alertItem = AlertItem(id: "AddServerExists")
            return
        }
        let ret = startLoadServerLibraries(calibreServer: calibreServer, parse: self.handleLibraryInfo(jsonData:)) {
            
            var content = "Library List:"
            calibreServerLibrariesEdit.removeAll()
            calibreServerLibrariesEdit.forEach {
                content += "\n\($0.name)"
            }

            alertContent = content
            alertItem = AlertItem(id: "AddServer")
        }
        
        if ret != 0 {
            switch(ret) {
            case 2: //URL malformed
                alertItem = AlertItem(id: "Server URL is not well formed")
                break;
            default:
                break;
            }
        }
    }
    
    private func addServerConfirmed() {
        let calibreServer = CalibreServer(name: calibreServerName, baseUrl: calibreServerUrl, publicUrl: calibreServerUrlPublic, username: calibreUsername, password: calibrePassword, defaultLibrary: calibreDefaultLibrary)
        
        modelData.addServer(server: calibreServer, libraries: calibreServerLibrariesEdit)
        modelData.currentCalibreServerId = calibreServer.id
        if let defaultLibraryId = calibreServerLibrariesEdit.filter({
            $0.name == $0.server.defaultLibrary
        }).first?.id {
            modelData.currentCalibreLibraryId = defaultLibraryId
        }
        calibreServerEditing = false
    }
    
    private func modServerConfirmButtonAction() {
        let newServer = CalibreServer(
            name: calibreServerName, baseUrl: calibreServerUrl, publicUrl: calibreServerUrlPublic, username: calibreUsername, password: calibrePassword)
        guard let server = modelData.currentCalibreServer else {
            alertItem = AlertItem(id: "ModServerNotExist")  //shouldn't reach here
            return
        }
        
        if newServer == server {
            //minor changes
            modelData.updateServer(newServer: newServer)
        } else {
            //sanity check
            let ret = startLoadServerLibraries(calibreServer: newServer, parse: self.handleLibraryInfo(jsonData:)) {
                
                
            }
            
            if ret != 0 {
                switch(ret) {
                case 2: //URL malformed
                    alertItem = AlertItem(id: "Server URL is not well formed")
                    break;
                default:
                    break;
                }
                return
            }
            
        }
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
}

struct ServerView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        ServerView()
            .environmentObject(modelData)
    }
}
