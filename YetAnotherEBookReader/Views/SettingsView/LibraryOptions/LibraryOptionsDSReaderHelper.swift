//
//  LibraryOptionsDSReaderHelper.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/22.
//

import SwiftUI
import Combine

struct LibraryOptionsDSReaderHelper: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.openURL) var openURL

    let library: CalibreLibrary     //should be identical with modelData.currentCalibreLibraryId
    
    @State var dsreaderHelperServer = CalibreServerDSReaderHelper(id: "", port: 0)
    @State var readingPosition = CalibreLibraryReadingPosition()
    @State var dsreaderHelperLibrary = CalibreLibraryDSReaderHelper()
    @State var goodreadsSync = CalibreLibraryGoodreadsSync()
    @State var countPages = CalibreLibraryCountPages()

    @State private var portStr = ""
    @State private var configurationData: Data? = nil
    @State private var configuration: CalibreDSReaderHelperConfiguration? = nil
    
    @State private var refreshCancellable: AnyCancellable? = nil

    @State private var helperStatus = ""
    
    @State private var configAlertItem: AlertItem?

    @State private var dsreaderHelperInstructionPresenting = false
    @State private var overrideMappingPresenting = false

    @Binding var updater: Int
    
    @State private var serverAddedCancellable: AnyCancellable?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DSReader Helper").font(.title3)
                Spacer()
                Button(action:{dsreaderHelperInstructionPresenting = true}) {
                    Image(systemName: "questionmark.circle")
                }
            }
            
            VStack(spacing: 4) {
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
                    Button(action:{
                        if dsreaderHelperServer.port < 65535 {
                            portStr = (dsreaderHelperServer.port+1).description
                        }
                    }) {
                        Image(systemName: "plus")
                    }
                }.padding([.leading, .trailing], 8)
                
                HStack {
                    Text(helperStatus)
                        
                    Spacer()
                    
                    Button(action: {
                        connect()
                    }) {
                        Text("Connect & Update Config")
                    }
                }
                .padding([.leading, .trailing], 8)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Store Reading Positions in Custom Column", isOn: $readingPosition._isEnabled)
                
                VStack(alignment: .leading, spacing: 4) {
                    if library.customColumnInfos.filter{ $1.datatype == "comments" }.count > 0 {
                        Picker("Column Name:     \(readingPosition.readingPositionCN)", selection: $readingPosition.readingPositionCN) {
                            ForEach(library.customColumnInfoCommentsKeys
                                        .map{ ($0.name, "#" + $0.label) }, id: \.1) {
                                Text("\($1)\n\($0)").tag($1)
                            }
                        }.pickerStyle(MenuPickerStyle())
                        .disabled(!readingPosition.isEnabled())
                    } else {
                        Text("no available column, please refresh library after adding column to calibre").font(.caption).foregroundColor(.red)
                    }
                }
                .padding([.leading, .trailing], 8)
            }
            .onChange(of: readingPosition) { [readingPosition] value in
                print("readingPosition change from \(readingPosition) to \(value)")
                if modelData.calibreLibraries[library.id]?.pluginReadingPositionWithDefault != value {
                    let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: value)
                }
            }
            
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Goodreads Sync Automation", isOn: $dsreaderHelperLibrary._isEnabled)
                
                Group {
                    HStack {
                        if let names = dsreaderHelperServer.configuration?.goodreads_sync_prefs?.plugin_prefs.Users.map{ $0.key }.sorted() {
                            Picker("Profile Name:     \(goodreadsSync.profileName)", selection: $goodreadsSync.profileName) {
                                ForEach(names, id: \.self) { name in
                                    Text(name)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        } else {
                            Text("Empty Profile List")
                        }
                    }
                    
                    Toggle("Auto Update Reading Progress", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsProgress)
                    
                    Toggle("Auto Update Book Shelf", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf)
                }
                .padding([.leading, .trailing], 8)
                .disabled( !dsreaderHelperLibrary.isEnabled() )
                
                if !(dsreaderHelperServer.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.goodreadsSyncEnabled ?? false) {
                    HStack {
                        Spacer()
                        Text("Plugin not available").font(.caption).foregroundColor(.red)
                    }
                }
            }
            .onChange(of: dsreaderHelperLibrary) { [dsreaderHelperLibrary] value in
                print("dsreaderHelperLibrary change from \(dsreaderHelperLibrary) to \(value)")
                if modelData.calibreLibraries[library.id]?.pluginDSReaderHelperWithDefault != value {
                    let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: value)
                }
            }
            .disabled(
                !(dsreaderHelperServer.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.goodreadsSyncEnabled ?? false)
            )
            
            Divider()
            
            
            Button(action: {
                overrideMappingPresenting = true
            }) {
                Text("Override Custom Column Mappings")
            }
            .sheet(isPresented: $overrideMappingPresenting, onDismiss: {
                if countPages != modelData.calibreLibraries[library.id]?.pluginCountPagesWithDefault {
                    let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: countPages)
                }
                
                if goodreadsSync != modelData.calibreLibraries[library.id]?.pluginGoodreadsSyncWithDefault {
                    let _ = modelData.updateLibraryPluginColumnInfo(libraryId: library.id, columnInfo: goodreadsSync)
                }
                
            }) {
                if let configuration = configuration {
                    LibraryOptionsOverrideCustomColumnMappings(
                        library: library, configuration: configuration, goodreadsSync: $goodreadsSync, countPages: $countPages)
                        .padding()
                        .frame(maxWidth: 600)
                } else {
                    Text("Unexpected error\nConfiguration not found")
                        .multilineTextAlignment(.center)
                }
            }
            .disabled(configuration == nil || modelData.calibreLibraries[library.id]?.customColumnInfos.isEmpty ?? true)
            
        }
        .onAppear() {
            setStates(libraryId: modelData.currentCalibreLibraryId)
            
            serverAddedCancellable = modelData.serverAddedPublisher.sink { notification in
                //Suppose setStates() has been called by "onChange(of: modelData.currentCalibreLibraryId)"
                print("serverAddedPublisher connect")
                connect()
            }
        }
        .onChange(of: modelData.currentCalibreLibraryId) { value in
            setStates(libraryId: value)
        }
        .onChange(of: updater) { _ in
            setStates(libraryId: modelData.currentCalibreLibraryId)
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
    
    private func setStates(libraryId: String) {
        guard let library = modelData.calibreLibraries[libraryId] else { return }
        let server = library.server
        let dsreaderHelperServer = modelData.queryServerDSReaderHelper(server: server) ?? {
            var dsreaderHelper = CalibreServerDSReaderHelper(id: server.id, port: 0)
            if let url = modelData.calibreServerService.getServerUrlByReachability(server: server) ?? URL(string: server.baseUrl) ?? URL(string: server.publicUrl) {
                dsreaderHelper.port = (url.port ?? -1) + 1
            }
            return dsreaderHelper
        }()
        
        configurationData = dsreaderHelperServer.configurationData
        configuration = dsreaderHelperServer.configuration
        
        readingPosition = library.pluginReadingPositionWithDefault ?? .init()
        dsreaderHelperLibrary = library.pluginDSReaderHelperWithDefault ?? .init()
        countPages = library.pluginCountPagesWithDefault ?? .init()
        goodreadsSync = library.pluginGoodreadsSyncWithDefault ?? .init()
        self.dsreaderHelperServer = dsreaderHelperServer
    }
    
    private func connect() {
        refreshCancellable?.cancel()
        configurationData = nil
        configuration = nil
        helperStatus = "Connecting"

        guard let library = modelData.currentCalibreLibrary else { return }
        
        let connector = DSReaderHelperConnector(calibreServerService: modelData.calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
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
                if let config = try? decoder.decode(CalibreDSReaderHelperConfiguration.self, from: data),
                   config.dsreader_helper_prefs != nil {
                    configuration = config
                    configurationData = data
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
                    
                    if library.server.username.isEmpty {
                        Text("Also note that server defaults to read-only mode when user authentication is not required, so please allow un-authenticated connection to make changes (\"Advanced\" tab in \"Sharing over the net\")")
                            .font(.caption)
                    }
                }
                
            }
        }
    }
    
}

struct LibraryOptionsDSReaderHelper_Previews: PreviewProvider {
    static private var modelData = ModelData()

    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")

    @State static private var dsreaderHelperServer = CalibreServerDSReaderHelper(id: library.server.id, port: 1234)
    @State static private var updater = 0
    static var previews: some View {
        LibraryOptionsDSReaderHelper(library: library, dsreaderHelperServer: dsreaderHelperServer, updater: $updater)
            .environmentObject(modelData)
        
        
    }
}
