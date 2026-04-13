//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/31.
//

import SwiftUI
import OSLog
import Combine

struct AddModServerView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.openURL) var openURL
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @Binding var server: CalibreServer
    @Binding var isActive: Bool
    
    // bindings for server editing
    @State private var calibreServerUUID = UUID()
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
    
    @State private var libraryList = [String]()
    
    @State private var isProbing = false
    
    @State private var calibreServerInfo: CalibreServerInfo? = nil

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
    
    fileprivate func processInputAction() {
        if server.baseUrl.isEmpty {
            dataAction = "Add"
            processUrlInputs()
            addServerConfirmButtonAction()
        } else {
            dataAction = "Mod"
            processUrlInputs()
            modServerConfirmButtonAction()
        }
        self.serverCalibreInfoPresenting = true
    }
    
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
                    
                    if modelData.isServerProbing(server: server) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text(calibreServerInfo?.errorMsg ?? "Unknown")
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
            disableProbeServerCancellable()
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
                    processInputAction()
                }) {
                    if isProbing {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(isProbing)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(action:{
                    resetStates()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(isProbing || modelData.isServerProbing(server: server))
            }
        }
        
    }
    
    @ViewBuilder
    func serverCalibreInfoSheetView() -> some View {
        Form {
            Section(header: Text("Server Status")) {
                if let serverInfo = calibreServerInfo {
                    Text(serverInfo.errorMsg)
                } else {
                    Text("Connecting")
                }
            }
            
            Section {
                Button(action: {
                    serverCalibreInfoPresenting = false
                }) {
                    Text("Cancel")
                }
                
                if calibreServerInfo?.errorMsg != "Success" {
                    Button {
                        calibreServerInfo?.errorMsg = "Connecting..."
                        processInputAction()
                    } label: {
                        Text("Retry")
                    }
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
                }.disabled(calibreServerInfo?.errorMsg != "Success")
            }
            
            Section(header: Text("Library List")) {
                if let serverInfo = calibreServerInfo,
                   serverInfo.errorMsg == "Success" {
                    ForEach(serverInfo.libraryMap.sorted(by: { $0.value < $1.value}), id: \.key) { libraryEntry in
                        HStack {
                            Text(libraryEntry.value)
                            Spacer()
                            if let info = self.modelData.calibreLibraryInfoStaging[CalibreLibrary(server: serverInfo.server, key: libraryEntry.key, name: libraryEntry.value).id] {
                                Text(info.errorMessage == "Success" ? "\(info.totalNumber) books" : info.errorMessage)
                            } else {
                                Text("Probing")
                            }
                        }
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
        
        if let existingServer = modelData.calibreServers.values.first(where: { server in
            server.baseUrl == calibreServerUrl
            && server.username == calibreUsername
            && server.removed == false
        }) {
            alertItem = AlertItem(id: "Exist", msg: "Conflict with \"\(existingServer.name)\"\nA server with the same address and username already exists")
            return
        }

        calibreServerUUID = .init()
        let calibreServer = CalibreServer(
            uuid: calibreServerUUID,
            name: calibreServerName,
            baseUrl: calibreServerUrl,
            hasPublicUrl: calibreServerSetPublicAddress,
            publicUrl: calibreServerUrlPublic,
            hasAuth: calibreServerNeedAuth,
            username: calibreUsername,
            password: calibrePassword
        )
        
//        modelData.calibreServerUpdating = true
//        if let task = modelData.calibreServerService.getServerLibraries(server: calibreServer) {
//            dataLoadingTask = task
//            serverCalibreInfoPresenting = true
//        } else {
//            alertItem = AlertItem(id: "Unexpected Error", msg: "Failed to connect to server")
//        }
        
        performProbeServer(server: calibreServer)
    }
    
    private func addServerConfirmed() {
        guard let serverInfo = calibreServerInfo else { return }
        
        var newServer = serverInfo.server
        newServer.defaultLibrary = serverInfo.defaultLibrary
        
        let libraries: [CalibreLibrary] = serverInfo.libraryMap
            .sorted { $0.key < $1.key }
            .map {
                .init(
                    server: serverInfo.server,
                    key: $0,
                    name: $1,
                    autoUpdate: false,
                    discoverable: true
                )
            }
        
        modelData.addServer(server: newServer, libraries: libraries)
        if let url = URL(string: newServer.baseUrl) {
            modelData.updateServerDSReaderHelper(
                serverId: newServer.id,
                dsreaderHelper: CalibreServerDSReaderHelper(
                    port: (url.port ?? -1) + 1
                ),
                realm: modelData.realm)
        }
        
        modelData.probeServersReachability(with: [newServer.id], updateLibrary: true, autoUpdateOnly: true)
        
        server = newServer
        isActive = false
    }
    
    private func modServerConfirmButtonAction() {
        calibreServerUUID = server.uuid
        let newServer = CalibreServer(
            uuid: calibreServerUUID,
            name: calibreServerName,
            baseUrl: calibreServerUrl,
            hasPublicUrl: calibreServerSetPublicAddress,
            publicUrl: calibreServerUrlPublic,
            hasAuth: calibreServerNeedAuth,
            username: calibreUsername,
            password: calibrePassword
        )
        
            if let existingServer = modelData.calibreServers.values.first(where: { server in
                server.uuid != newServer.uuid
                && server.baseUrl == newServer.baseUrl
                && server.username == newServer.username
                && server.removed == false
            }) {
                alertItem = AlertItem(id: "Exist", msg: "Conflict with \"\(existingServer.name)\"\nA server with the same address and username already exists")
                return
            }

//            modelData.calibreServerUpdating = true
            
//            if let task = modelData.calibreServerService.getServerLibraries(server: newServer) {
//                dataLoadingTask = task
//                serverCalibreInfoPresenting = true
//            } else {
//                alertItem = AlertItem(id: "Unexpected Error", msg: "Failed to connect to server")
//            }
            
            performProbeServer(server: newServer)
    }
    
    private func modServerConfirmed() {
        guard let serverInfo = calibreServerInfo else {
            alertItem = AlertItem(id: "Error", msg: "Unexpected Error")
            return
        }
        
        var newServer = serverInfo.request.server
        newServer.defaultLibrary = serverInfo.defaultLibrary
        newServer.removed = server.removed
        
        server = newServer
        
        isActive = false
    }
    
    private func performProbeServer(server: CalibreServer) {
        isProbing = true
        Task {
            let serverInfo = await modelData.probeServer(request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true, incremental: true))
            
            await MainActor.run {
                if let serverInfo = serverInfo {
                    serverInfo.libraryMap.forEach { key, name in
                        Task {
                            await modelData.probeLibrary(request: .init(library: .init(server: serverInfo.request.server, key: key, name: name)))
                        }
                    }
                    self.calibreServerInfo = serverInfo
                }
                isProbing = false
            }
        }
    }
    
    private func disableProbeServerCancellable() {
        self.calibreServerInfo = nil
        self.isProbing = false
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
