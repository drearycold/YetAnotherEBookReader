//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/31.
//

import SwiftUI
import OSLog

struct AddModServerView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.openURL) var openURL

    @Binding var server: CalibreServer
    @Binding var isActive: Bool
    
    // bindings for server editing
    @State private var calibreServerName = ""
    @State private var calibreServerUrl = ""
    @State private var calibreServerUrlWelformed = ""
    @State private var calibreServerUrlPublic = ""
    @State private var calibreServerSetPublicAddress = false
    @State private var calibreServerNeedAuth = false
    @State private var calibreUsername = ""
    @State private var calibrePassword = ""
    @State private var calibrePasswordVisible = false
    
    @State private var dataAction: String?
    @State private var dataLoadingTask: URLSessionDataTask? = nil
    
    @State private var libraryList = [String]()
    
    @State private var serverCalibreInfoPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($serverCalibreInfoPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var localLibraryImportBooksPicked = [URL]()
    @State private var localLibraryImportPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($localLibraryImportPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var updater = 0
    
    var defaultLog = Logger()
    
    @State private var alertItem: AlertItem?
    
    var body: some View {
        Form {
            Section(
                header: Text("Basic"),
                footer: Text(calibreServerUrlWelformed)
                        .font(.caption).foregroundColor(.red)
            ) {
                textFieldView(label: "Name", title: "Name Your Server", text: $calibreServerName, original: server.name)
                textFieldView(label: "URL", title: "Internal Server Address", text: $calibreServerUrl, original: server.baseUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
            }
            Section(
                header: Text("Internet Access"),
                footer: HStack {
                    Text("It's highly recommended to enable HTTPS and user authentication before exposing server to Internet.")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        .font(.caption)
                    Spacer()
                    Button(action:{
                        guard let url = URL(string: "https://manual.calibre-ebook.com/server.html#accessing-the-server-from-anywhere-on-the-internet") else { return }
                        openURL(url)
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                }
            ) {
                Toggle("Internet Accessible", isOn: $calibreServerSetPublicAddress)
                textFieldView(label: "Address", title: "Public Server Address", text: $calibreServerUrlPublic, original: server.publicUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                .disabled(!calibreServerSetPublicAddress)
            }
            Section(header: Text("Authentication")) {
                Toggle("Require", isOn: $calibreServerNeedAuth)
                
                Group {
                    textFieldView(label: "Username", title: "Username", text: $calibreUsername, original: server.username)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    secureFieldView(label: "Password", title: "", text: $calibrePassword, visible: $calibrePasswordVisible, original: server.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }.disabled(!calibreServerNeedAuth)
            }
            
            Section(
                header: HStack {
                    Text("Status")
                    
                    Spacer()
                    
                    if modelData.calibreServerUpdating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text(modelData.calibreServerUpdatingStatus ?? "Unknown")
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
                },
                footer: HStack(alignment: .center, spacing: 8) {
                    Spacer()
                    Text("Got \(libraryList.count) Library(s) in Server")
                }
            ) {
                if libraryList.isEmpty {
                    Text("No Library")
                } else {
                    ForEach(libraryList, id: \.self) { name in
                        Text(name).font(.callout)
                    }
                }
            }
        }
        .onAppear {
            resetStates()
        }
        .sheet(isPresented: $serverCalibreInfoPresenting, onDismiss: {
            dataAction = nil
            dataLoadingTask?.cancel()
            dataLoadingTask = nil
            modelData.calibreServerUpdating = false
        }, content: {
            serverCalibreInfoSheetView()
        })
        .alert(item: $alertItem) { item in
            if item.id == "Exist" {
                return Alert(
                    title: Text("\(dataAction ?? "") Server Errer"),
                    message: Text(item.msg ?? ""),
                    dismissButton: .cancel(){
                        alertItem = nil
                    }
                )
            }
            return Alert(title: Text("Unknown Error"), message: Text(item.id + "\n" + (item.msg ?? "")), dismissButton: .cancel() {
                item.action?()
            })
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    if server.baseUrl.isEmpty {
                        dataAction = "Add"
                        processUrlInputs()
                        addServerConfirmButtonAction()
                    } else {
                        dataAction = "Mod"
                        processUrlInputs()
                        modServerConfirmButtonAction()
                    }
                }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(modelData.calibreServerUpdating)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(action:{
                    resetStates()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(modelData.calibreServerUpdating)
            }
        }
        
    }
    
    @ViewBuilder
    func serverCalibreInfoSheetView() -> some View {
        List {
            Section(header: Text("Server Status")) {
                Text(modelData.calibreServerUpdating ? "Connecting" : modelData.calibreServerUpdatingStatus ?? "Unexcepted Error")
            }
            
            Button(action: {
                serverCalibreInfoPresenting = false
            }) {
                Text("Cancel")
            }
            
            Button(action: {
                if dataAction == "Add" {
                    addServerConfirmed()
                } else if dataAction == "Mod" {
                    modServerConfirmed()
                }
                serverCalibreInfoPresenting = false
            }) {
                if dataAction == "Add" {
                    Text("Add")
                } else if dataAction == "Mod" {
                    Text("Update")
                } else {
                    Text("OK")
                }
            }.disabled(modelData.calibreServerUpdatingStatus != "Success")
            
            Section(header: Text("Library List")) {
                if let updatingStatus = modelData.calibreServerUpdatingStatus,
                   updatingStatus == "Success",
                   let serverInfo = modelData.calibreServerInfo {
                    ForEach(serverInfo.libraryMap.values.sorted(), id: \.self) {
                        Text($0)
                    }
                } else {
                    Text("Cannot Fetch Library List")
                }
                
            }
        }
    }
    
    @ViewBuilder
    private func textFieldView(label: String, title: String, text: Binding<String>, original: String, onEditingChanged: @escaping (Bool) -> Void = { _ in }, onCommit: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 4) {
            Text(label)
            TextField(title, text: text, onEditingChanged: onEditingChanged, onCommit: onCommit)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
            Button(action:{ text.wrappedValue.removeAll() }) {
                Image(systemName: "xmark.circle.fill")
            }
            if original.isEmpty == false {
                Button(action:{ text.wrappedValue = original }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    @ViewBuilder
    private func secureFieldView(label: String, title: String, text: Binding<String>, visible: Binding<Bool>, original: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Button(action:{
                visible.wrappedValue.toggle()
            }) {
                Image(systemName: visible.wrappedValue ? "eye" : "eye.slash")
            }
            Group {
                if visible.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            
            Button(action:{ text.wrappedValue.removeAll() }) {
                Image(systemName: "xmark.circle.fill")
            }
            if original.isEmpty == false {
                Button(action:{ text.wrappedValue = original }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    private func resetStates() {
        calibreServerName = server.name
        calibreServerUrl = server.baseUrl
        calibreUsername = server.username
        calibrePassword = server.password
        calibreServerUrlPublic = server.publicUrl
        calibreServerSetPublicAddress = server.hasPublicUrl
        calibreServerNeedAuth = server.hasAuth
        libraryList = modelData.calibreLibraries.values.filter{ $0.server.id == server.id }.map{ $0.name }.sorted()
    }
    
    private func canDeleteCurrentServer() -> Bool {
        return !server.isLocal
    }
    
    private func processUrlInputs() {
        if calibreServerUrl != server.baseUrl {
            if calibreServerUrl.contains("://") == false {
                calibreServerUrl = "http://" + calibreServerUrl
            }
            if var components = URLComponents(string: calibreServerUrl) {
                if components.scheme == nil {
                    components.scheme = "http://"
                }
                if components.path == "" {
                    components.path = "/"
                }
                if let s = components.string {
                    calibreServerUrl = s
                }
            }
        }
        if calibreServerUrlPublic != server.publicUrl, var components = URLComponents(string: calibreServerUrlPublic) {
            if components.scheme == nil {
                components.scheme = "http://"
            }
            if components.path == "" {
                components.path = "/"
            }
            if let s = components.string {
                calibreServerUrlPublic = s
            }
        }
    }
    
    private func addServerConfirmButtonAction() {
        if calibreServerName.isEmpty {
            if let url = URL(string: calibreServerUrl), let host = url.host {
                calibreServerName = host
            } else {
                calibreServerName = "Unnamed"
            }
        }
        let calibreServer = CalibreServer(
            uuid: .init(), name: calibreServerName, baseUrl: calibreServerUrl, hasPublicUrl: calibreServerSetPublicAddress, publicUrl: calibreServerUrlPublic, hasAuth: calibreServerNeedAuth, username: calibreUsername, password: calibrePassword)
        if let existingServer = modelData.calibreServers[calibreServer.id] {
            alertItem = AlertItem(id: "Exist", msg: "Conflict with \"\(existingServer.name)\"\nA server with the same address and username already exists")
            return
        }

        modelData.calibreServerUpdating = true
        if let task = modelData.calibreServerService.getServerLibraries(server: calibreServer) {
            dataLoadingTask = task
            serverCalibreInfoPresenting = true
        } else {
            alertItem = AlertItem(id: "Unexpected Error", msg: "Failed to connect to server")
        }
    }
    
    private func addServerConfirmed() {
        guard let serverInfo = modelData.calibreServerInfo else { return }
        
        var newServer = serverInfo.server
        newServer.defaultLibrary = serverInfo.defaultLibrary
        newServer.lastLibrary = serverInfo.defaultLibrary
        
        let libraries = serverInfo.libraryMap
            .sorted { $0.key < $1.key }
            .map { CalibreLibrary(server: serverInfo.server, key: $0, name: $1) }
        
        modelData.addServer(server: newServer, libraries: libraries)
        if let url = URL(string: newServer.baseUrl) {
            modelData.updateServerDSReaderHelper(
                dsreaderHelper: CalibreServerDSReaderHelper(
                    id: newServer.id,
                    port: (url.port ?? -1) + 1
                ),
                realm: modelData.realm)
        }
        
        modelData.probeServersReachability(with: [newServer.id], updateLibrary: true, autoUpdateOnly: false, disableAutoThreshold: 999)
        
        server = newServer
        isActive = false
    }
    
    private func modServerConfirmButtonAction() {
        let newServer = CalibreServer(
            uuid: server.uuid,
            name: calibreServerName, baseUrl: calibreServerUrl, hasPublicUrl: calibreServerSetPublicAddress, publicUrl: calibreServerUrlPublic, hasAuth: calibreServerNeedAuth, username: calibreUsername, password: calibrePassword)
        
        if newServer.id == server.id {
            //minor changes
//            modelData.updateServer(oldServer: server, newServer: newServer)
            server = newServer
            isActive = false
        } else {
            if let existingServer = modelData.calibreServers[newServer.id] {
                alertItem = AlertItem(id: "Exist", msg: "Conflict with \"\(existingServer.name)\"\nA server with the same address and username already exists")
                return
            }

            modelData.calibreServerUpdating = true
            
            if let task = modelData.calibreServerService.getServerLibraries(server: newServer) {
                dataLoadingTask = task
                serverCalibreInfoPresenting = true
            } else {
                alertItem = AlertItem(id: "Unexpected Error", msg: "Failed to connect to server")
            }
        }
    }
    
    private func modServerConfirmed() {
        guard let serverInfo = modelData.calibreServerInfo else {
            alertItem = AlertItem(id: "Error", msg: "Unexpected Error")
            return
        }
        
        var newServer = serverInfo.server
        newServer.defaultLibrary = serverInfo.defaultLibrary
        newServer.lastLibrary = server.lastLibrary
        
        server = newServer
        
        isActive = false
    }
}

extension AddModServerView : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

struct AddModServerView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)
    
    @State static private var server = CalibreServer(uuid: .init(), name: "TestName", baseUrl: "TestBase", hasPublicUrl: true, publicUrl: "TestPublic", hasAuth: true, username: "TestUser", password: "TestPswd")
    @State static private var addServerActive = false

    static var previews: some View {
        NavigationView {
            AddModServerView(server: $server, isActive: $addServerActive)
                .environmentObject(modelData)
                .onAppear() {
                    modelData.calibreServers[server.id] = server
                    let library = CalibreLibrary(server: server, key: "TestKey", name: "TestName")
                    modelData.calibreLibraries[library.id] = library
                }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
