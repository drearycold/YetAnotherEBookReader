//
//  ServerOptionsDSReaderHelper.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/22.
//

import SwiftUI

struct ServerOptionsDSReaderHelper: View {
    @Environment(\.openURL) var openURL

    @ObservedObject var viewModel: ServerViewModel
    @Binding var server: CalibreServer
    
    @Binding var updater: Int
    
    var body: some View {
        let configuration = viewModel.savedHelper?.configuration
        let validPorts = CalibreServerDSReaderHelper.validPorts
        Form {
            Section {
                HStack {
                    Text("Plugin Service Port")
                    Spacer()
                    TextField("Plugin Service Port", text: $viewModel.portStr)
                        .frame(idealWidth: 80, maxWidth: 80)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("server.helper.port")

                    Button {
                        if let port = viewModel.helperPort { viewModel.portStr = String(port - 1) }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Decrease plugin service port")
                    .disabled((viewModel.helperPort ?? validPorts.lowerBound) <= validPorts.lowerBound)

                    Button {
                        if let port = viewModel.helperPort { viewModel.portStr = String(port + 1) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Increase plugin service port")
                    .disabled((viewModel.helperPort ?? validPorts.upperBound) >= validPorts.upperBound)
                }
                if viewModel.helperPort == nil {
                    Text(HelperConfigurationFailure.invalidPort.message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            switch viewModel.helperState {
            case .loading:
                Section {
                    ProgressView("Downloading configuration…")
                    Button("Cancel Download", action: viewModel.stopHelperConfiguration)
                }
            case .failure(let failure):
                Section {
                    Text(failure.message)
                        .accessibilityIdentifier("server.helper.failure")
                }
            case .cancelled:
                Text("Download cancelled.")
            case .idle, .awaitingConfirmation:
                EmptyView()
            }

            Section(header: Text("Supported server plugins")) {
                NavigationLink(
                    destination: List {
                        ForEach (
                            configuration?.count_pages_prefs?.library_config?.map {
                                (key: $0.key, value: $0.value) }.sorted { $0.key < $1.key } ?? [], id: \.key
                        ) { key, value in
                            Section(header: Text("Library \(key)")) {
                                Group {
                                    Text("Pages: \(value.customColumnPages.isEmpty ? "not set" : value.customColumnPages)")
                                    Text("Words: \(value.customColumnWords.isEmpty ? "not set" : value.customColumnWords)")
                                    Text("Flesch Reading: \(value.customColumnFleschReading.isEmpty ? "not set" : value.customColumnFleschReading)")
                                    Text("Flesch Grade: \(value.customColumnFleschGrade.isEmpty ? "not set" : value.customColumnFleschGrade)")
                                    Text("Gunning Fog: \(value.customColumnGunningFog.isEmpty ? "not set" : value.customColumnGunningFog)")
                                }
                                .font(.callout)
                            }
                        }
                    }
                        .navigationTitle("Count Pages Columns")
                ) {
                    HStack {
                        Text("Count Pages")
                        Spacer()
                        if configuration?.count_pages_prefs?.library_config?.count ?? 0 > 0 {
                            Text("detected")
                        } else {
                            Text("missing")
                        }
                    }
                }

                NavigationLink(
                    destination: List{
                        ForEach (
                            configuration?.goodreads_sync_prefs?.plugin_prefs.Users.map {
                                (key: $0.key, value: $0.value) }.sorted { $0.key < $1.key } ?? [], id: \.key
                        ) { user_entry in
                            Section(header: Text("Profile \(user_entry.key)")) {
                                goodreadsSyncDetailsShelf(user_entry: user_entry)
                                    .font(.callout)
                            }
                        }
                    }
                        .navigationTitle("Goodreads Sync Profiles")
                ) {
                    HStack {
                        Text("Goodreads Sync")
                        Spacer()
                        if configuration?.goodreads_sync_prefs?.plugin_prefs.Users.count ?? 0 > 0 {
                            Text("detected")
                        } else {
                            Text("missing")
                        }
                    }

                }

                HStack {
                    Text("Dictionary Viewer")
                    Spacer()
                    if let options = configuration?.dsreader_helper_prefs?.plugin_prefs.Options,
                       options.dictViewerEnabled,
                       options.dictViewerLibraryName.count > 0 {
                        Text("Enabled\nUsing Library \(options.dictViewerLibraryName)")
                            .font(.caption2)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("server.helper.dictionary-library")
                    } else {
                        Text("missing")
                    }

                }
            }
        }
        .navigationTitle("DSReader Helper")
        .toolbar {
            // iOS 15 exposes only one item at this placement.
            ToolbarItem(placement: .navigationBarTrailing) {
                HelperConfigurationToolbar(viewModel: viewModel, serverID: server.id)
            }
        }
        .onAppear { viewModel.openHelperConfiguration(serverID: server.id) }
        .onDisappear(perform: viewModel.closeHelperConfiguration)
        .onChange(of: DSReaderHelperConnection(server)) { _ in
            viewModel.openHelperConfiguration(serverID: server.id)
        }
        .onChange(of: updater) { _ in
            viewModel.openHelperConfiguration(serverID: server.id)
        }
        .alert(item: $viewModel.helperConfirmation) { ticket in
            Alert(
                title: Text("Use DSReader Helper Config?"),
                message: Text("Update the saved plugin settings with the downloaded configuration?"),
                primaryButton: .default(Text("Update")) {
                    viewModel.applyHelperConfiguration(ticket, serverID: server.id)
                },
                secondaryButton: .cancel {
                    viewModel.discardHelperConfiguration(ticket)
                }
            )
        }
        .sheet(isPresented: $viewModel.dsreaderHelperInstructionPresenting, content: {
            instructions()
                .padding()
        })
    }
    
    @ViewBuilder
    private func goodreadsSyncDetailsShelf(user_entry: (key: String, value: CalibreGoodreadsSyncPrefs.Shelves)) -> some View {
        ForEach (
            user_entry.value.shelves, id: \.self
        ) { shelf in
            HStack {
                Text("Shelf \(shelf.name)")
                Spacer()
                Text("\(shelf.book_count) books")
                    .frame(minWidth: 80, alignment: .trailing)
            }
        }
    }
    
    @ViewBuilder
    private func instructions() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                
                Text("Instructions on setting DSReader Helper plugin").font(.title2)
                
                Group {
                    Text("Get it to work").font(.title3)
                        .padding([.top], 4).padding([.leading], 8)
                    
                    Text("Kindly please download latest release from our homepage at:")
                    Button(action:{
                        openURL(URL(string: "https://dsreader.github.io/")!)
                    }) {
                        Text("https://dsreader.github.io/")
                    }
                    
                    Text("After installing and restarting calibre, please open plugin option to let it finish setting its custom columns.")
                    
                    Text("By default DSReader Helper will listen on port (1 + calibre's port number). You can change it to another port number if needed, and please make sure it is open for access if you have firewall.")
                }
                
                Group {
                    Text("Why another plugin?").font(.title3)
                        .padding([.top], 4).padding([.leading], 8)
                    
                    Text("calibre has a good wealth of great plugins, and we want to make use of them to enrich DSReader's reading experiences. However, plugins' functionalities are not exposed by calibre context server APIs. Therefore we have made a helper plugin for this purpose.")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Through this plugin DSReader will be able to:")
                        Text("• Pulling other plugins' custom columns settings. Currently supports \"Count Pages\" and \"Goodreads Sync\"")
                        Text("• Tapping into other plugins' functionalities. Currently supports automatically updating reading progress and book shelf to Goodreads using \"Goodreads Sync\"")
                        Text("• Managing reading positions across multiple devices more effectively and robust.")
                    }
                    
                    Text("DSReader Helper has reused calibre Content Server's HTTP service components. Therefore this port has the same safety measures as calibre itself. Restrictions to User account should work as intended.")

                }
                
            }
        }
    }
}

private struct HelperConfigurationToolbar: View {
    @ObservedObject var viewModel: ServerViewModel
    let serverID: String

    var body: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.connectDSReader(serverID: serverID)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Download Helper Configuration")
            .accessibilityIdentifier("server.helper.download")
            .disabled(viewModel.helperPort == nil)

            Button {
                viewModel.dsreaderHelperInstructionPresenting = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("DSReader Helper Instructions")
        }
    }
}

struct ServerOptionsDSReaderHelper_Previews: PreviewProvider {
    static private var container = AppContainer()

    @State static private var server = CalibreServer(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
    @State static private var updater = 0
    static var previews: some View {
        let viewModel = ServerViewModel(container: container, server: server)
        NavigationView {
            ServerOptionsDSReaderHelper(viewModel: viewModel, server: $server, updater: $updater)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
