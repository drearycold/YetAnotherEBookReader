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
                                print("library set \(newLibrary)")
                                libraryList.forEach {
                                    print("libraryList setter \($0)")
                                }
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
                Text("\(modelData.queryLibraryBookRealmCount(library: library, realm: modelData.realm)) books")
                Text("PLACEHOLDER")
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
                
                if modelData.librarySyncStatus[library.id] ?? (false, false, "") == (false, false, "Success") {
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
                    modelData.librarySyncStatus[library.id] = (true, false, "")
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
                var library = results.library
                print("\(#function) receiveValue \(library.id)")

                guard results.result["just_syncing"] == nil else { return }
                var isError = false
                
                defer {
                    DispatchQueue.main.async {
                        modelData.librarySyncStatus[library.id]?.isSync = false
                        modelData.librarySyncStatus[library.id]?.isError = isError
                        print("\(#function) finishSync \(library.id)")
                    }
                }
                
                guard results.result["error"] == nil else {
                    isError = true
                    return
                }
                
                if let result = results.result["result"] {
                    library.customColumnInfos = result
                    
                    DispatchQueue.main.async {
                        try? modelData.updateLibraryRealm(library: library)
                        modelData.calibreLibraries[library.id] = library
                        modelData.librarySyncStatus[library.id]?.msg = "Success"
                    }
                }
                
                guard results.list.book_ids.contains(-1) == false else {
                    isError = true
                    return
                }
                
                guard let realm = try? Realm(configuration: modelData.realmConf) else {
                    isError = true
                    return
                }
                results.list.book_ids.forEach { id in
                    let idStr = id.description
                    
                    try? realm.write {
                        let obj = realm.objects(CalibreBookRealm.self).filter(
                            NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@ AND id = %@",
                                        results.library.server.baseUrl,
                                        results.library.server.username,
                                        results.library.name,
                                        NSNumber(value: id)
                            )
                        ).first ?? CalibreBookRealm()
                        
                        if obj.id == 0 {
                            obj.serverUrl = results.library.server.baseUrl
                            obj.serverUsername = results.library.server.username
                            obj.libraryName = results.library.name
                            obj.id = id
                        }
                        
                        obj.title = results.list.data.title[idStr] ?? "Untitled"
                        obj.authors.removeAll()
                        obj.authors.append(objectsIn: results.list.data.authors[idStr] ?? ["Unknown"])
                        
                        obj.series = (results.list.data.series[idStr] ?? "") ?? ""
                        obj.seriesIndex = results.list.data.series_index[idStr] ?? 0
                        obj.identifiersData = try? JSONEncoder().encode(results.list.data.identifiers[idStr]) as NSData?
                        
                        
                        if let formatsResult = results.list.data.formats[idStr] {
                            var formats = (
                                try? JSONDecoder().decode(
                                    [String:FormatInfo].self,
                                    from: obj.formatsData as Data? ?? Data()
                                )
                            ) ?? [:]
                            formats = formatsResult.reduce(into: formats) { result, newFormat in
                                if result[newFormat] == nil {
                                    result[newFormat] = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
                                }
                            }
                            formats
                                .map { $0.key }
                                .filter { formatsResult.contains($0) == false }
                                .forEach {
                                    formats.removeValue(forKey: $0)
                                }
                            
                            obj.formatsData = try? JSONEncoder().encode(formats) as NSData?
                        }
                        
                        realm.add(obj, update: .modified)
                    }
                }
                
                if modelData.currentCalibreLibraryId == library.id {
                    DispatchQueue.main.async {
                        modelData.currentCalibreLibraryId = ""
                        modelData.currentCalibreLibraryId = library.id
                    }
                }
                
                updater += 1
            }
    }
}

struct ServerDetailView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var server = modelData.currentCalibreServer ?? .init(name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default")
    
    static var previews: some View {
        ServerDetailView(server: $server)
            .environmentObject(modelData)
    }
}
