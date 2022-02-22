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
    
    @State private var dataAction = ""
    @State private var dataLoading = false
    
    @State private var libraryList = [String]()
    @State private var libraryListExpanded = false
    
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                textFieldView(label: "Name", title: "Name Your Server", text: $calibreServerName, original: server.name)
                textFieldView(label: "URL", title: "Internal Server Address", text: $calibreServerUrl, original: server.baseUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Text(calibreServerUrlWelformed)
                    .font(.caption).foregroundColor(.red)
                
                VStack(spacing: 8) {
                    Toggle("Set a Separate Public Address", isOn: $calibreServerSetPublicAddress)
                    Group {
                        if calibreServerSetPublicAddress {
                            textFieldView(label: "Public", title: "Public Server Address", text: $calibreServerUrlPublic, original: server.publicUrl)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)

                            HStack {
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
                        }
                    }.padding([.leading, .trailing], 8)
                }
                VStack(spacing: 8) {
                    Toggle("Need Authentication", isOn: $calibreServerNeedAuth)
                    
                    Group {
                        if calibreServerNeedAuth {
                            textFieldView(label: "Username", title: "Username", text: $calibreUsername, original: server.username)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            secureFieldView(label: "Password", title: "", text: $calibrePassword, visible: $calibrePasswordVisible, original: server.password)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                        }
                    }.padding([.leading, .trailing], 8)
                }
                
                HStack {
                    if dataLoading {
                        Text("Connecting...")
                    } else {
                        Text(modelData.calibreServerUpdatingStatus ?? "")
                    }
                    
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
                        Spacer()
                        
                        Text("Got \(libraryList.count) Library(s) in Server")
                        
                        Button(action: {
                            dataAction = "Sync"
                            processUrlInputs()
                            dataLoading = true  //ready for consuming results
                            modelData.calibreServerService.getServerLibraries(server: server)
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        
                        Button(action:{
                            libraryListExpanded.toggle()
                        }) {
                            Image(systemName: libraryListExpanded ? "chevron.up" : "chevron.down")
                        }
                    }
                }
                
                if libraryListExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(libraryList, id: \.self) { name in
                            Text(name).font(.callout)
                        }
                    }.padding()
                }
            }
        }
        .onAppear {
            resetStates()
        }
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
                return Alert(title: Text("Add Server Error"), message: Text("A server with the same address and username already exists"), dismissButton: .cancel())
            }
            if item.id == "ModServerExists" {
                return Alert(title: Text("Modify Server Errer"), message: Text("A server with the same address and username already exists"), dismissButton: .cancel())
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
                    message: Text("Will Remove Cached Book List and Book Files from Reader, Everything on Server will Stay Intact. (OR in the case of Local Library, remove ALL imported books.)"),
                    primaryButton: .destructive(Text("Confirm")) {
                        delLibraryConfirmed()
                    },
                    secondaryButton: .cancel()
                )
            }
            if item.id == "ModServer" {
                return Alert(title: Text("Mod Server"),
                             message: { if let msg = item.msg {return Text(msg)} else {return nil} }(),
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
            if dataAction == "Test" {
                if newStatus == "Success" {
                    dataLoading = false
                    libraryList = serverInfo.libraryMap.values.sorted()
                    libraryListExpanded = true
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
            
        }.toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    dataAction = "Test"
                    processUrlInputs()
                    testServerConfirmButtonAction()
                }) {
                    Text("Test")
                }
            }
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
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(action:{
                    resetStates()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }.frame(maxWidth: 720)
        .padding(.all, 8)
        .disabled(modelData.calibreServerUpdating || modelData.calibreServerLibraryUpdating || dataLoading)
        
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
            name: calibreServerName, baseUrl: calibreServerUrl, hasPublicUrl: calibreServerSetPublicAddress, publicUrl: calibreServerUrlPublic, hasAuth: calibreServerNeedAuth, username: calibreUsername, password: calibrePassword)
        if modelData.calibreServers[calibreServer.id] != nil {
            alertItem = AlertItem(id: "AddServerExists")
            return
        }

        dataLoading = true
        modelData.calibreServerService.getServerLibraries(server: calibreServer)
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
        modelData.currentCalibreServerId = newServer.id
        if let defaultLibraryId = libraries.filter({
            $0.name == $0.server.defaultLibrary
        }).first?.id {
            modelData.currentCalibreLibraryId = defaultLibraryId
        }
        modelData.probeServersReachability(with: [newServer.id])
        
        server = newServer
        isActive = false
        
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(200))) {
            NotificationCenter.default.post(Notification(name: .YABR_ServerAdded))
        }
    }
    
    private func modServerConfirmButtonAction() {
        let newServer = CalibreServer(
            name: calibreServerName, baseUrl: calibreServerUrl, hasPublicUrl: calibreServerSetPublicAddress, publicUrl: calibreServerUrlPublic, hasAuth: calibreServerNeedAuth, username: calibreUsername, password: calibrePassword)
        
        if newServer.id == server.id {
            //minor changes
//            modelData.updateServer(oldServer: server, newServer: newServer)
            server = newServer
            isActive = false
        } else {
            if modelData.calibreServers[newServer.id] != nil {
                alertItem = AlertItem(id: "ModServerExists")
                return
            }

            dataLoading = true
            modelData.calibreServerService.getServerLibraries(server: newServer)
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
        
        // modelData.updateServer(oldServer: server, newServer: newServer)
        server = newServer
        
        modelData.probeServersReachability(with: [newServer.id])

        isActive = false
    }
    
    private func testServerConfirmButtonAction() {
        let newServer = CalibreServer(
            name: calibreServerName, baseUrl: calibreServerUrl, hasPublicUrl: calibreServerSetPublicAddress, publicUrl: calibreServerUrlPublic, hasAuth: calibreServerNeedAuth, username: calibreUsername, password: calibrePassword)
        
        dataLoading = true
        modelData.calibreServerService.getServerLibraries(server: newServer)
    }
    
    private func delServerConfirmed() {
        let isSuccess = modelData.removeServer(serverId: server.id)
        if !isSuccess {
            alertItem = AlertItem(id: "DelServerFailed")
        } else {
            isActive = false
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

extension AddModServerView : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

struct AddModServerView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)
    
    @State static private var server = CalibreServer(name: "TestName", baseUrl: "TestBase", hasPublicUrl: true, publicUrl: "TestPublic", hasAuth: true, username: "TestUser", password: "TestPswd")
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
        }
    }
}
