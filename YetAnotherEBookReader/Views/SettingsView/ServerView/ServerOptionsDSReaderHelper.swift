//
//  LibraryOptionsDSReaderHelper.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/22.
//

import SwiftUI
import Combine

struct ServerOptionsDSReaderHelper: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.openURL) var openURL

    @Binding var server: CalibreServer
    @State var dsreaderHelperServer = CalibreServerDSReaderHelper(id: "", port: 0)
    
    @State private var portStr = ""
    @State private var configurationData: Data? = nil
    @State private var configuration: CalibreDSReaderHelperConfiguration? = nil
    
    @State private var refreshCancellable: AnyCancellable? = nil

    @State private var helperStatus = ""
    
    @State private var configAlertItem: AlertItem?

    @State private var readingPositionDetails = false
    @State private var dictionaryViewerDetails = false
    @State private var countPagesDetails = false
    @State private var goodreadsSyncDetails = false
    
    @State private var dsreaderHelperInstructionPresenting = false

    @Binding var updater: Int
    
    @State private var serverAddedCancellable: AnyCancellable?
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Plugin Service Port")
                    
                    Spacer()
                    
                    TextField("Plugin Service Port", text: $portStr)
                        .frame(idealWidth: 80, maxWidth: 80)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .onReceive(Just(portStr)) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if let num = Int(filtered), num != dsreaderHelperServer.port {
                                if num > 65535 {
                                    dsreaderHelperServer.port = 65535
                                } else if num < 1024 {
                                    dsreaderHelperServer.port = 1024
                                } else {
                                    dsreaderHelperServer.port = num
                                }
                            }
                        }
                        .onChange(of: dsreaderHelperServer.port, perform: { value in
                            portStr = value.description
                        })
                    
                    Button(action:{
                        if dsreaderHelperServer.port > 1024 {
                            portStr = (dsreaderHelperServer.port-1).description
                        }
                    }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action:{
                        if dsreaderHelperServer.port < 65535 {
                            portStr = (dsreaderHelperServer.port+1).description
                        }
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
                
            Section(header: Text("Supported server plugins")) {
                NavigationLink(
                    destination: List {
                        ForEach (
                            configuration?.count_pages_prefs?.library_config.map {
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
                        if configuration?.count_pages_prefs?.library_config.count ?? 0 > 0 {
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
                    } else {
                        Text("missing")
                    }
                    
                }
            }
        }
        .navigationTitle("DSReader Helper")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    connect()
                }) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    dsreaderHelperInstructionPresenting = true
                }) {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .onAppear() {
            setStates()
        }
        .onChange(of: updater) { _ in
            setStates()
        }
        .alert(item: $configAlertItem) { item in
            if item.id == "updateConfigAlert" {
                return Alert(title: Text("Use DSReader Helper Config?"),
                      message: Text("Successfully downloaded helper plugin configurations from server, update local settings?"),
                      primaryButton: .default(Text("Update"), action: update),
                      secondaryButton: .cancel({
                        dsreaderHelperServer.configuration = nil
                        dsreaderHelperServer.configurationData = nil
                      }))
            }
            if item.id == "failedParseConfigAlert" {
                return Alert(title: Text("Failed to Parse Result"),
                      message: Text("Please double check service port number"),
                      dismissButton: .cancel(Text("Dismiss"))
                )
            }
            if item.id == "failedConnectConfigAlert" {
                return Alert(title: Text("DSReader Helper Unavaiable"),
                      message: Text("Have you installed DSReader Helper plugin on calibre server?\nThe plugin will greatly enhance this App's abilty to interact with services provided by your favorite calibre plugins. We highly recommend you look into it."),
                      primaryButton: .default(Text("Great, show me"), action: {dsreaderHelperInstructionPresenting = true}),
                      secondaryButton: .cancel(Text("Maybe Later"))
                )
            }
            return Alert(title: Text("Unexpected"))
        }
        .sheet(isPresented: $dsreaderHelperInstructionPresenting, content: {
            instructions()
                .padding()
        })
    }
    
    private func setStates() {
        let dsreaderHelperServer = modelData.queryServerDSReaderHelper(server: server) ?? {
            var dsreaderHelper = CalibreServerDSReaderHelper(id: server.id, port: 0)
            if let url = modelData.calibreServerService.getServerUrlByReachability(server: server) ?? URL(string: server.baseUrl) ?? URL(string: server.publicUrl) {
                dsreaderHelper.port = (url.port ?? -1) + 1
            }
            return dsreaderHelper
        }()
        
        configurationData = dsreaderHelperServer.configurationData
        configuration = dsreaderHelperServer.configuration
        
        self.dsreaderHelperServer = dsreaderHelperServer
        portStr = dsreaderHelperServer.port.description
    }
    
    private func connect() {
        refreshCancellable?.cancel()
        configurationData = nil
        configuration = nil
        helperStatus = "Connecting..."

        let connector = DSReaderHelperConnector(calibreServerService: modelData.calibreServerService, server: server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
        refreshCancellable = connector.refreshConfiguration()?
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { complete in
                print("receiveCompletion \(complete)")
                switch(complete) {
                case .finished:
                    break
                default:
                    helperStatus = "Failed to Connect"
                    configAlertItem = AlertItem(id: "failedConnectConfigAlert")
                }
            }, receiveValue: { data in
                let decoder = JSONDecoder()
                var config: CalibreDSReaderHelperConfiguration? = nil
                do {
                    config = try decoder.decode(CalibreDSReaderHelperConfiguration.self, from: data.data)
                } catch {
                    print(error)
                }
                if let config = config, config.dsreader_helper_prefs != nil {
                    configuration = config
                    configurationData = data.data	
                    helperStatus = "Connected"

                    configAlertItem = AlertItem(id: "updateConfigAlert")
                } else {
                    helperStatus = "Failed"
//                    failedParseConfigAlertPresenting = true
                    configAlertItem = AlertItem(id: "failedParseConfigAlert")
                }
            })
    }
    
    private func update() {
        guard let configuration = configuration else { return }
        dsreaderHelperServer.configuration = configuration
        dsreaderHelperServer.configurationData = configurationData
        
        modelData.updateServerDSReaderHelper(dsreaderHelper: dsreaderHelperServer, realm: modelData.realm)
    }
    
    @ViewBuilder
    private func readingPositionDetailsUser(library_entry: (key: String, value: CalibreReadingPositionPrefs.ReadingPositionLibraryConfig)) -> some View {
        if library_entry.value.readingPositionColumns.isEmpty {
            Text("None Exists")
        } else {
            ForEach (
                library_entry.value.readingPositionColumns.map { (key: $0.key, value: $0.value) }.sorted { $0.key < $1.key } , id: \.key
            ) { user_entry in
                HStack {
                    Text("User: \(user_entry.key)")
                    Spacer()
                    Text("Column \(user_entry.value.label)")
                }
            }
        }
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
                
                Group {
                    Text("Enable Reading Position Syncing without DSReader Helper plugin").font(.title2)
                        .padding([.top], 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("If you remain wary of our plugin, reading position syncing can still work without it.")
                        
                        Text("Please add a custom column of type \"Long text, like comments\" on calibre server.")
                        
                        Text("If there are multiple users, it's better to add a unique column for each user.")
                        
                        Text("Defaults to #read_pos[_username].")
                    }    .font(.callout)
                    
                    if server.username.isEmpty {
                        Text("Also note that server defaults to read-only mode when user authentication is not required, so please allow un-authenticated connection to make changes (\"Advanced\" tab in \"Sharing over the net\")")
                            .font(.caption)
                    }
                }
                
            }
        }
    }
    
}

struct ServerOptionsDSReaderHelper_Previews: PreviewProvider {
    static private var modelData = ModelData()

    @State static private var server = CalibreServer(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")

    @State static private var dsreaderHelperServer = CalibreServerDSReaderHelper(id: server.id, port: 1234)
    @State static private var updater = 0
    static var previews: some View {
        NavigationView {
            ServerOptionsDSReaderHelper(server: $server, dsreaderHelperServer: dsreaderHelperServer, updater: $updater)
                .environmentObject(modelData)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
