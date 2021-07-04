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
    
    @State private var calibreServerId = ""
    @State private var calibreServerLibraryId = "Undetermined"
    
    @State private var calibreServerUrl = ""
    @State private var calibreServerNeedAuth = false
    @State private var calibreUsername = ""
    @State private var calibrePassword = ""
    //@State private var calibreServerEdit = CalibreServer(baseUrl: "", username: "", password: "")
    @State private var calibreServerLibrariesEdit = [CalibreLibrary]()
    
    @State private var enableStoreReadingPosition = false
    @State private var storeReadingPositionColumnName = ""
    
    @State private var enableGoodreadsSync = false
    @State private var goodreadsSyncProfileName = ""
    
    
    @State private var calibreServerEditing = false
    
    @State private var presentingAlert = false
    
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
                    Picker("Switch Server", selection: $calibreServerId) {
                        ForEach(modelData.calibreServers.values.sorted(by: { (lhs, rhs) -> Bool in
                            lhs.id < rhs.id
                        }), id: \.self) { server in
                            Text(server.id).tag(server.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: calibreServerId) { value in
                        if modelData.currentCalibreServerId != calibreServerId {
                            modelData.currentCalibreServerId = calibreServerId
                        }
                    }
                    
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
                    }
                    Button(action:{
                        //TODO modify current server
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    if calibreServerEditing {
                        HStack {
                            Text("Server:")
                            TextField("Server", text: $calibreServerUrl)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))
                            
                        }
                        
                        Toggle("Auth?", isOn: $calibreServerNeedAuth)
                        
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
                            Spacer()
                            Button(action:{ calibreServerEditing = false }) {
                                Image(systemName: "xmark")
                            }
                            Button(action:{ addServerConfirmButtonAction() }) {
                                Image(systemName: "checkmark")
                            }
                        }
                        
                        
                    } else {
                        Text("Current Server: \(modelData.currentCalibreServerId)")
                        
                        HStack(alignment: .center, spacing: 8) {
                            Spacer()
                            
                            Text("\(modelData.calibreLibraries.values.filter({ (library) -> Bool in library.server.id == calibreServerId }).count) Library(s) in Server")
                            
                            Button(action: {
                                let ret = startLoadServerLibraries(
                                    calibreServer: modelData.calibreServers[modelData.currentCalibreServerId]!,
                                    success: modelData.handleLibraryInfo(jsonData:)
                                )
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
                    Picker("Switch Library", selection: $calibreServerLibraryId) {
                        ForEach(modelData.calibreLibraries.values.filter({ (library) -> Bool in
                            library.server.id == calibreServerId
                        }).sorted(by: { (lhs, rhs) -> Bool in
                            lhs.name < rhs.name
                        })) { library in
                            Text(library.name).tag(library.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: calibreServerLibraryId, perform: { value in
                        if modelData.currentCalibreLibraryId != calibreServerLibraryId {
                            modelData.currentCalibreLibraryId = calibreServerLibraryId
                        }
                        
                        guard let library = modelData.calibreLibraries[calibreServerLibraryId] else { return }
                        
                        enableStoreReadingPosition = library.readPosColumnName != nil
                        storeReadingPositionColumnName = library.readPosColumnName ?? library.readPosColumnNameDefault
                        
                        enableGoodreadsSync = library.goodreadsSyncProfileName != nil
                        goodreadsSyncProfileName = library.goodreadsSyncProfileName ?? library.goodreadsSyncProfileNameDefault
                    })
                    
                    Text("Current Library: \(modelData.calibreLibraries[modelData.currentCalibreLibraryId]?.name ?? "")")
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
                    }
                    
                    Toggle("Enable Goodreads Sync", isOn: $enableGoodreadsSync)
                        .onChange(of: enableGoodreadsSync, perform: { value in
                            modelData.updateGoodreadsSyncProfileName(enabled: value, value: goodreadsSyncProfileName)
                        })
                    Text("This is a Work-in-Progress, please stay tuned!")
                        .font(.caption)
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
                    }
                }
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .disabled(dataLoading)
            .disabled(modelData.calibreServerLibraryUpdating)
            
            Spacer()
        }
        .onAppear() {
            calibreServerId = modelData.currentCalibreServerId
            calibreServerLibraryId = modelData.currentCalibreLibraryId
            
            if let library = modelData.calibreLibraries[calibreServerLibraryId] {
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
                    message: Text("Will Remove Cached Libraries and Books from App"),
                    primaryButton: .default(Text("Confirm")) {
                        delServerConfirmed()
                    },
                    secondaryButton: .cancel()
                )
            }
            return Alert(title: Text("Error"), message: Text(item.id), dismissButton: .cancel() {
                item.action?()
            })
        }
    }
    
    
    
    private func syncLibrary() {
        print(modelData.calibreLibraries)
        print(modelData.currentCalibreLibraryId)
        guard let endpointUrl = URL(string: modelData.calibreServers[modelData.currentCalibreServerId]!.baseUrl + "/cdb/cmd/list/0?library_id=" + modelData.calibreLibraries[modelData.currentCalibreLibraryId]!.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else {
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
    
    func startLoadServerLibraries(calibreServer: CalibreServer, success: @escaping (_ jsonData: Data) -> Void) -> Int {
        if dataLoading {
            return 1
        }
        guard let url = URL(string: calibreServer.baseUrl + "/ajax/library-info") else {
            return 2
        }
        if calibreServer.username.count > 0 && calibreServer.password.count > 0 {
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            let userCredential = URLCredential(user: calibreServer.username,
                                               password: calibreServer.password,
                                               persistence: .permanent)
            URLCredentialStorage.shared.setDefaultCredential(userCredential, for: protectionSpace)
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print(error.localizedDescription)
                self.alertItem = AlertItem(id: error.localizedDescription, action: {
                    dataLoading = false
                })
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                self.alertItem = AlertItem(id: response?.description ?? "nil reponse", action: {
                    dataLoading = false
                })
                return
            }
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data {
                DispatchQueue.main.async {
                    success(data)
                    dataLoading = false
                }
            }
        }
        
        dataLoading = true
        task.resume()
        return 0
    }
    
    func handleLibraryInfo(jsonData: Data) {
        var calibreServer = CalibreServer(baseUrl: calibreServerUrl, username: calibreUsername, password: calibrePassword)
        
        if let libraryInfo = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? NSDictionary {
            defaultLog.info("libraryInfo: \(libraryInfo)")
            
            if let libraryMap = libraryInfo["library_map"] as? [String: String] {
                if let defaultLibrary = libraryInfo["default_library"] as? String {
                    calibreServer.defaultLibrary = defaultLibrary
                }
                if calibreServer.lastLibrary.isEmpty {
                    calibreServer.lastLibrary = calibreServer.defaultLibrary
                }
                var content = "Library List:"
                calibreServerLibrariesEdit.removeAll()
                libraryMap.forEach { (key, value) in
                    content += "\n\(value)"
                    calibreServerLibrariesEdit.append(CalibreLibrary(server: calibreServer, key: key, name: value))
                }
                
                alertContent = content
                alertItem = AlertItem(id: "AddServer")
            }
            
        } else {
            
        }
    }
    
    private func addServerConfirmButtonAction() {
        let calibreServer = CalibreServer(baseUrl: calibreServerUrl, username: calibreUsername, password: calibrePassword)
        if modelData.calibreServers[calibreServer.id] != nil {
            alertItem = AlertItem(id: "AddServerExists")
            return
        }
        print(calibreServer.password)
        let ret = startLoadServerLibraries(calibreServer: calibreServer, success: self.handleLibraryInfo(jsonData:))
        switch(ret) {
        case 2: //URL malformed
            alertItem = AlertItem(id: "Server URL is not well formed")
            break;
        default:
            break;
        }
    }
    
    private func addServerConfirmed() {
        let calibreServer = CalibreServer(baseUrl: calibreServerUrl, username: calibreUsername, password: calibrePassword)
        
        modelData.addServer(server: calibreServer, libraries: calibreServerLibrariesEdit)
        calibreServerId = calibreServer.id
        if let defaultLibraryId = calibreServerLibrariesEdit.filter({
            $0.name == $0.server.defaultLibrary
        }).first?.id {
            calibreServerLibraryId = defaultLibraryId
        }
        calibreServerEditing = false
    }
    
    private func delServerConfirmed() {
        
    }
}

struct ServerView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        ServerView()
            .environmentObject(modelData)
    }
}
