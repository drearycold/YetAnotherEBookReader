//
//  AddModServerView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/31.
//

import SwiftUI
import OSLog

struct AddModServerView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.openURL) var openURL
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @ObservedObject var viewModel: ServerViewModel
    @Binding var server: CalibreServer
    @Binding var isActive: Bool
    
    @State private var localLibraryImportBooksPicked = [URL]()
    @State private var localLibraryImportPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($localLibraryImportPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    var body: some View {
        Form {
            Section(
                header: Text("Basic"),
                footer: Text(viewModel.calibreServerUrlWelformed)
                        .font(.caption).foregroundColor(.red)
            ) {
                textFieldView(label: "Name", title: "Name Your Server", text: $viewModel.calibreServerName, original: server.name)
                textFieldView(label: "URL", title: "Internal Server Address", text: $viewModel.calibreServerUrl, original: server.baseUrl)
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
                Toggle("Internet Accessible", isOn: $viewModel.calibreServerSetPublicAddress)
                textFieldView(label: "Address", title: "Public Server Address", text: $viewModel.calibreServerUrlPublic, original: server.publicUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                .disabled(!viewModel.calibreServerSetPublicAddress)
            }
            Section(header: Text("Authentication")) {
                Toggle("Require", isOn: $viewModel.calibreServerNeedAuth)
                
                Group {
                    textFieldView(label: "Username", title: "Username", text: $viewModel.calibreUsername, original: server.username)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    secureFieldView(label: "Password", title: "", text: $viewModel.calibrePassword, visible: $viewModel.calibrePasswordVisible, original: server.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }.disabled(!viewModel.calibreServerNeedAuth)
            }
            
            Section(
                header: HStack {
                    Text("Status")
                    
                    Spacer()
                    
                    if modelData.isServerProbing(server: server) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text(viewModel.calibreServerInfo?.errorMsg ?? "Unknown")
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
                    Text("Got \(viewModel.libraryList.count) Library(s) in Server")
                }
            ) {
                if viewModel.libraryList.isEmpty {
                    Text("No Library")
                } else {
                    ForEach(viewModel.libraryList, id: \.self) { name in
                        Text(name).font(.callout)
                    }
                }
            }
        }
        .onAppear {
            viewModel.resetStates(server: server)
        }
        .sheet(isPresented: $viewModel.serverCalibreInfoPresenting, onDismiss: {
            viewModel.dataAction = nil
            viewModel.disableProbeServerCancellable()
        }, content: {
            serverCalibreInfoSheetView()
        })
        .alert(item: $viewModel.alertItem) { item in
            if item.id == "Exist" {
                return Alert(
                    title: Text("\(viewModel.dataAction ?? "") Server Error"),
                    message: Text(item.msg ?? ""),
                    dismissButton: .cancel(){
                        viewModel.alertItem = nil
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
                    viewModel.processInputAction(server: server) {}
                }) {
                    if viewModel.isProbing {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(viewModel.isProbing || modelData.isServerProbing(server: server))
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(action:{
                    viewModel.resetStates(server: server)
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(viewModel.isProbing || modelData.isServerProbing(server: server))
            }
        }
    }
    
    @ViewBuilder
    func serverCalibreInfoSheetView() -> some View {
        Form {
            Section(header: Text("Server Status")) {
                if let serverInfo = viewModel.calibreServerInfo {
                    Text(serverInfo.errorMsg)
                } else {
                    Text("Connecting")
                }
            }
            
            Section {
                Button(action: {
                    viewModel.serverCalibreInfoPresenting = false
                }) {
                    Text("Cancel")
                }
                
                if viewModel.calibreServerInfo?.errorMsg != "Success" {
                    Button {
                        viewModel.calibreServerInfo?.errorMsg = "Connecting..."
                        viewModel.processInputAction(server: server) {}
                    } label: {
                        Text("Retry")
                    }
                }
                
                Button(action: {
                    if viewModel.dataAction == "Add" {
                        viewModel.addServerConfirmed(serverBinding: $server, isActiveBinding: $isActive)
                    } else if viewModel.dataAction == "Mod" {
                        viewModel.modServerConfirmed(serverBinding: $server, isActiveBinding: $isActive)
                    }
                    viewModel.serverCalibreInfoPresenting = false
                }) {
                    if viewModel.dataAction == "Add" {
                        Text("Add")
                    } else if viewModel.dataAction == "Mod" {
                        Text("Update")
                    } else {
                        Text("OK")
                    }
                }.disabled(viewModel.calibreServerInfo?.errorMsg != "Success")
            }
            
            Section(header: Text("Library List")) {
                if let serverInfo = viewModel.calibreServerInfo,
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
}

struct AddModServerView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)
    
    @State static private var server = CalibreServer(uuid: .init(), name: "TestName", baseUrl: "TestBase", hasPublicUrl: true, publicUrl: "TestPublic", hasAuth: true, username: "TestUser", password: "TestPswd")
    @State static private var addServerActive = false

    static var previews: some View {
        let viewModel = ServerViewModel(modelData: modelData, server: server)
        NavigationView {
            AddModServerView(viewModel: viewModel, server: $server, isActive: $addServerActive)
                .environmentObject(modelData)
                .onAppear() {
                    modelData.calibreServers[server.id] = server
                    let library = CalibreLibrary(server: server, key: "TestKey", name: "TestName")
                    modelData.calibreLibraries[library.id] = library
                }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
