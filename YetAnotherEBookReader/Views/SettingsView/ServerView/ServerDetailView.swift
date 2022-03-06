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
    
    @State private var libraryList = [CalibreLibrary]()

    @State private var syncingLibrary = false
    @State private var syncLibraryColumnsCancellable: AnyCancellable? = nil
    
    @State private var updater = 0
    
    var body: some View {
//        ScrollView {
        List {
            Text("Server Options")
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
            ForEach(libraryList, id: \.self) { library in
                NavigationLink(
                    destination: LibraryDetailView(
                        library: Binding<CalibreLibrary>(
                            get: {
                                library
                            },
                            set: { newLibrary in
                                libraryList.removeAll(where: {$0.id == newLibrary.id})
                                libraryList.append(newLibrary)
                                sortLibraryList()
                                modelData.calibreLibraries[newLibrary.id] = newLibrary
                                try? modelData.updateLibraryRealm(library: newLibrary, realm: modelData.realm)
                            }
                        )
                    ),
                    tag: library.id,
                    selection: $selectedLibrary) {
                    libraryRowBuilder(library: library)
                }
            }
            
        }
        .navigationTitle(server.name)
        .onAppear() {
            libraryList = modelData.calibreLibraries.values.filter{ library in
                library.server.id == server.id
            }
            sortLibraryList()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    syncLibraries()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }.disabled(syncingLibrary)
            }
        }
        .onDisappear() {
            syncLibraryColumnsCancellable?.cancel()
        }
    }

    private func sortLibraryList() {
        libraryList.sort { $0.name < $1.name }
    }
    
    private func setStates() {
        // dictionaryViewer = library.pluginDictionaryViewerWithDefault ?? .init()
    }
    
    @ViewBuilder
    private func libraryRowBuilder(library: CalibreLibrary) -> some View {
        HStack(spacing: 8) {
            Text(library.name)
            Spacer()
            VStack(alignment: .trailing) {
                if let cnt = modelData.librarySyncStatus[library.id]?.cnt {
                    Text("\(cnt) books")
                } else {
                    Text("processing")
                }
                Text("PLACEHOLDER").hidden()
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
    
    //MARK: model functionalities
    private func syncLibraries() {
        syncingLibrary = true

        let list = libraryList  //.filter { $0.name == "AAA-Test" }
        syncLibraryColumnsCancellable = list.publisher
            .flatMap { library -> AnyPublisher<CalibreCustomColumnInfoResult, Never> in
                guard (modelData.librarySyncStatus[library.id]?.isSync ?? false) == false else {
                    print("\(#function) isSync \(library.id)")
                    return Just(CalibreCustomColumnInfoResult(library: library, result: ["just_syncing":[:]]))
                        .setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                DispatchQueue.main.sync {
                    if modelData.librarySyncStatus[library.id] == nil {
                        modelData.librarySyncStatus[library.id] = (false, false, "", nil)
                    }
                    modelData.librarySyncStatus[library.id]?.isSync = true
                    modelData.librarySyncStatus[library.id]?.cnt = nil
                }
                print("\(#function) startSync \(library.id)")

                return modelData.calibreServerService.getCustomColumnsPublisher(library: library)
            }
            .flatMap { customColumnResult -> AnyPublisher<CalibreCustomColumnInfoResult, Never> in
                print("\(#function) syncLibraryPublisher \(customColumnResult.library.id)")
                return modelData.calibreServerService.syncLibraryPublisher(resultPrev: customColumnResult)
            }
            .subscribe(on: DispatchQueue.global())
            .sink { complete in
                if complete == .finished {
                    DispatchQueue.main.async {
                        list.forEach {
                            modelData.librarySyncStatus[$0.id]?.isSync = false
                        }
                        syncingLibrary = false
                    }
                }
            } receiveValue: { results in
                self.modelData.syncLibrariesSinkValue(results: results)
                
                updater += 1
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
