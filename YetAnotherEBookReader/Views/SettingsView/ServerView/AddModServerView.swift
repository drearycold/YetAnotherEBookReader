//
//  AddModServerView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/31.
//

import SwiftUI

struct AddModServerView: View {
    @Environment(\.openURL) private var openURL

    @ObservedObject var viewModel: ServerConnectionEditorViewModel
    var browseAfterAdding = false
    var onConfirm: (ServerConnectionEditorViewModel.Confirmation) -> Void = { _ in }
    let onFinish: () -> Void
    var onCancel: (() -> Void)?
    @State private var confirmed = false

    private var usesResultSheet: Bool {
        if #available(iOS 16, *) { return true }
        return false
    }

    var body: some View {
        ZStack {
            if viewModel.resultPresented && !usesResultSheet {
                // iOS 15 can leave the underlying navigation unresponsive after a nested sheet closes.
                serverCalibreInfoSheetView()
            } else {
                editorForm
            }
        }
        .onAppear(perform: viewModel.startEditing)
        .onDisappear {
            if !viewModel.resultPresented { viewModel.endEditing() }
        }
        .sheet(isPresented: Binding(
            get: { usesResultSheet && viewModel.resultPresented },
            set: { viewModel.resultPresented = $0 }
        ), onDismiss: finishResult) {
            serverCalibreInfoSheetView()
        }
        .alert(item: $viewModel.alertItem) { item in
            if item.id == "Exist" {
                return Alert(
                    title: Text(viewModel.isAdding ? "Add Server Error" : "Modify Server Error"),
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
    }

    private var editorForm: some View {
        Form {
            if !viewModel.editTargetAvailable {
                Text("This server is no longer available.")
            }
            Section(header: Text("Basic")) {
                textFieldView(label: "Name", title: "Name Your Server", text: $viewModel.draft.name, original: viewModel.originalServer?.name ?? "")
                textFieldView(label: "URL", title: "Internal Server Address", text: $viewModel.draft.internalAddress, original: viewModel.originalServer?.baseUrl ?? "")
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
                Toggle("Internet Accessible", isOn: $viewModel.draft.usePublicAddress)
                textFieldView(label: "Address", title: "Public Server Address", text: $viewModel.draft.publicAddress, original: viewModel.originalServer?.publicUrl ?? "")
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                .disabled(!viewModel.draft.usePublicAddress)
            }
            Section(header: Text("Authentication")) {
                Toggle("Require", isOn: $viewModel.draft.requiresAuthentication)
                
                Group {
                    textFieldView(label: "Username", title: "Username", text: $viewModel.draft.username, original: viewModel.originalServer?.username ?? "")
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    secureFieldView(label: "Password", title: "", text: $viewModel.draft.password, visible: $viewModel.passwordVisible, original: viewModel.originalServer?.password ?? "")
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }.disabled(!viewModel.draft.requiresAuthentication)
            }
            
            Section(
                header: HStack {
                    Text("Status")
                    
                    Spacer()
                    
                    if viewModel.isBusy {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text(viewModel.serverInfo.map { ServerConnectionStatus(info: $0).title } ?? "Unknown")
                            .lineLimit(2)
                    }

                    if let reachable = viewModel.reachability.privateAddress {
                        Image(
                            systemName: reachable ? "flag.circle" : "flag.slash.circle"
                        ).foregroundColor(reachable ? .green : .red)
                    }

                    if let reachable = viewModel.reachability.publicAddress {
                        Image(
                            systemName: reachable ? "flag" : "flag.slash"
                        ).foregroundColor(reachable ? .green : .red)
                    }
                },
                footer: HStack(alignment: .center, spacing: 8) {
                    Spacer()
                    Text("Got \(viewModel.knownLibraryNames.count) Library(s) in Server")
                }
            ) {
                if viewModel.knownLibraryNames.isEmpty {
                    Text("No Library")
                } else {
                    ForEach(viewModel.knownLibraryNames, id: \.self) { name in
                        Text(name).font(.callout)
                    }
                }
            }
        }
        .accessibilityIdentifier("server.connection.form")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    viewModel.connect()
                }) {
                    if viewModel.isProbing {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        if browseAfterAdding {
                            Text("Connect")
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
                .accessibilityIdentifier("server.connection.connect")
                .disabled(viewModel.isBusy || !viewModel.editTargetAvailable)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(action:{
                    if browseAfterAdding {
                        viewModel.endEditing()
                        onCancel?()
                    } else {
                        viewModel.resetDraft()
                    }
                }) {
                    if browseAfterAdding {
                        Text("Cancel")
                    } else {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .accessibilityIdentifier("server.connection.cancel")
                .disabled(!browseAfterAdding && viewModel.isBusy)
            }
        }
    }
    
    @ViewBuilder
    func serverCalibreInfoSheetView() -> some View {
        Form {
            Section(header: Text("Server Status")) {
                Text(viewModel.connectionStatus.title)
                    .font(.headline)
                    .accessibilityIdentifier("server.connection.status.title")
                if let message = viewModel.connectionStatus.message {
                    Text(message)
                        .accessibilityIdentifier("server.connection.status.message")
                }
            }
            
            Section {
                if !viewModel.isProbing && !viewModel.canConfirmServer {
                    Button("Edit Connection") {
                        viewModel.dismissResult()
                    }
                    .accessibilityIdentifier("server.connection.edit")
                }
                if !viewModel.canConfirmServer {
                    Button("Retry") {
                        viewModel.connect()
                    }
                    .accessibilityIdentifier("server.connection.retry")
                    .disabled(viewModel.isProbing)
                }
                Button(action: {
                    viewModel.dismissResult()
                }) {
                    Text("Cancel")
                }
                .accessibilityIdentifier("server.connection.result.cancel")
                
                Button(action: {
                    if let confirmation = viewModel.confirm(browseAfterAdding: browseAfterAdding) {
                        onConfirm(confirmation)
                        if usesResultSheet {
                            confirmed = true
                        } else {
                            viewModel.dismissResult()
                            onFinish()
                            return
                        }
                    }
                    viewModel.dismissResult()
                }) {
                    if viewModel.isAdding {
                        Text(browseAfterAdding ? "Add and Browse Library" : "Add")
                    } else {
                        Text("Update")
                    }
                }
                .accessibilityIdentifier("server.connection.confirm")
                .disabled(!viewModel.canConfirmServer || (browseAfterAdding && viewModel.libraryToBrowse == nil))
            }

            if viewModel.canConfirmServer {
                let libraries = viewModel.librariesFromProbe
                let requiresSelection = browseAfterAdding && libraries.count > 1
                Section(
                    header: Text(browseAfterAdding ? "Library to Browse" : "Library List"),
                    footer: Text(requiresSelection ? "Choose a library to browse. All libraries will be added." : "")
                ) {
                    ForEach(libraries, id: \.key) { library in
                        if requiresSelection {
                            Button {
                                viewModel.browseLibraryID = library.id
                            } label: {
                                HStack {
                                    libraryInfoRow(library)
                                    Image(systemName: viewModel.browseLibraryID == library.id ? "checkmark.circle.fill" : "circle")
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("server.connection.library.\(library.key)")
                            .accessibilityAddTraits(viewModel.browseLibraryID == library.id ? .isSelected : [])
                        } else {
                            libraryInfoRow(library)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("server.connection.result")
    }

    private func finishResult() {
        viewModel.dismissResult()
        guard confirmed else { return }
        confirmed = false
        onFinish()
    }

    private func libraryInfoRow(_ library: CalibreLibrary) -> some View {
        HStack {
            Text(library.name)
            Spacer()
            Text(viewModel.libraryProbeStatus(for: library.id))
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
            .accessibilityIdentifier("server.connection.field.\(label).clear")
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
    static private var container = AppContainer(mock: true)

    static var previews: some View {
        NavigationView {
            AddModServerView(
                viewModel: ServerConnectionEditorViewModel(container: container, mode: .add),
                onFinish: {}
            )
        }.navigationViewStyle(.stack)
    }
}
