//
//  ServerDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2022/2/14.
//

import SwiftUI
import Combine
import RealmSwift

struct ServerDetailView: View {
    @EnvironmentObject var modelData: ModelData

    @Binding var server: CalibreServer
    @State private var selectedLibrary: String? = nil
    
    @State private var modServerActive = false
    @State private var dshelperActive = false
    
    @State private var dictionaryViewer = CalibreLibraryDictionaryViewer()
    
    @State private var libraryList = [String]()

    @State private var syncingLibrary = false
    @State private var syncLibraryColumnsCancellable: AnyCancellable? = nil
    
    @State private var updater = 0
    
    var body: some View {
//        ScrollView {
        List {
            HStack {
                Text("Options")
                Spacer()
                if let serverInfo = modelData.getServerInfo(server: server) {
                    if serverInfo.reachable {
                        Text("Server has \(serverInfo.libraryMap.count) libraries")
                    } else {
                        Text("\(serverInfo.errorMsg)")
                            .foregroundColor(.red)
                    }
                }
            }
            .font(.caption)
            .padding([.top], 16)
            
            NavigationLink(
                destination: AddModServerView(server: $server, isActive: $modServerActive)
                    .navigationTitle("Modify: \(server.name)"),
                isActive: $modServerActive,
                label: {
                    Text("Modify Configuration")
                }
            )
            
            NavigationLink(
                destination: LibraryOptionsDSReaderHelper(server: $server, updater: $updater),
                label: {
                    Text("DSReader Helper")
                })
            
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Dictionary Viewer", isOn: $dictionaryViewer._isEnabled)
            }
            
            HStack {
                Text("Libraries")
                    .font(.caption)
                    .padding([.top], 16)
                    Spacer()
                    
            }
            ForEach(libraryList, id: \.self) { id in
                NavigationLink(
                    destination: LibraryDetailView(
                        library: Binding<CalibreLibrary>(
                            get: {
                                modelData.calibreLibraries[id]!
                            },
                            set: { newLibrary in
                                modelData.calibreLibraries[id] = newLibrary
                                try? modelData.updateLibraryRealm(library: newLibrary, realm: modelData.realm)
                            }
                        ),
                        discoverable: Binding<Bool>(get: {
                            modelData.calibreLibraries[id]!.discoverable
                        }, set: { newValue in
                            modelData.calibreLibraries[id]!.discoverable = newValue
                            try? modelData.updateLibraryRealm(library: modelData.calibreLibraries[id]!, realm: modelData.realm)
                            NotificationCenter.default.post(Notification(name: .YABR_BooksRefreshed))
                        }),
                        autoUpdate: Binding<Bool>(get: {
                            modelData.calibreLibraries[id]!.autoUpdate
                        }, set: { newValue in
                            modelData.calibreLibraries[id]!.autoUpdate = newValue
                            try? modelData.updateLibraryRealm(library: modelData.calibreLibraries[id]!, realm: modelData.realm)
                        })
                    ),
                    tag: id,
                    selection: $selectedLibrary) {
                    libraryRowBuilder(library: modelData.calibreLibraries[id]!)
                }
            }
            
        }
        .navigationTitle(server.name)
        .onAppear() {
            libraryList = modelData.calibreLibraries.values.filter{ library in
                library.server.id == server.id
            }
            .sorted{ $0.name < $1.name }
            .map { $0.id }
            
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    modelData.probeServersReachability(with: [server.id], updateLibrary: true, autoUpdateOnly: false)
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }.disabled(syncingLibrary)
            }
        }
        .onDisappear() {
            syncLibraryColumnsCancellable?.cancel()
        }
    }

    @ViewBuilder
    private func libraryRowBuilder(library: CalibreLibrary) -> some View {
        HStack(spacing: 8) {
            if library.autoUpdate {
                Image(systemName: "play.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "play.slash.fill")
                    .foregroundColor(.red)
            }
            if library.discoverable {
                Image(systemName: "eye.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "eye.slash.fill")
                    .foregroundColor(.red)
            }
                
            Text(library.name)
            
            Spacer()
            VStack(alignment: .trailing) {
                if let cnt = modelData.librarySyncStatus[library.id]?.cnt {
                    Text("\(cnt) books")
                } else {
                    Text("processing")
                }
                if modelData.librarySyncStatus[library.id]?.isError == true {
                    Text("Status Unknown")
                } else if let cnt = modelData.librarySyncStatus[library.id]?.cnt, let upd = modelData.librarySyncStatus[library.id]?.upd {
                    if upd > 0, cnt > upd {
                        Text("\(upd) entries lagging")
                    }
                } else if modelData.librarySyncStatus[library.id]?.isSync == false {
                    Text("Insufficient Info")
                }
            }.font(.caption2)
            ZStack {
                if modelData.librarySyncStatus[library.id]?.isSync ?? false {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .hidden()
                }
                
                if let status = modelData.librarySyncStatus[library.id],
                   status.isSync == false,
                   status.isError == false,
                   status.msg == "Success" {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .hidden()
                }
                
                if modelData.librarySyncStatus[library.id]?.isSync == false,
                   modelData.librarySyncStatus[library.id]?.isError == true {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .hidden()
                }
            }
        }
    }

}

struct ServerDetailView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var server = modelData.calibreServers.values.first ?? .init(name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default")
    
    static var previews: some View {
        ServerDetailView(server: $server)
            .environmentObject(modelData)
    }
}
