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
    
    @State private var libraryList = [String]()

    @State private var syncingLibrary = false
    @State private var syncLibraryColumnsCancellable: AnyCancellable? = nil
    
    @State private var updater = 0
    
    @State private var libraryRestoreListActive = false
    @State private var libraryRestoreListEditMode = EditMode.active
    @State private var libraryRestoreListSelection = Set<String>()
    
    var body: some View {
        Form {
            Section(header: Text("Options")) {
                NavigationLink(
                    destination: AddModServerView(server: $server, isActive: $modServerActive)
                        .navigationTitle("Modify: \(server.name)"),
                    isActive: $modServerActive,
                    label: {
                        Text("Modify Configuration")
                    }
                )
                .isDetailLink(false)
                
                NavigationLink(
                    destination: ServerOptionsDSReaderHelper(server: $server, updater: $updater),
                    isActive: $dshelperActive,
                    label: {
                        Text("DSReader Helper")
                    }
                )
                .isDetailLink(false)
            }
            
            Section(header: librarySectionHeader()) {
                ForEach(libraryList.compactMap { modelData.calibreLibraries[$0] }, id: \.self) { library in
                    NavigationLink(
                        destination: libraryEntryDestination(library: library),
                        tag: library.id,
                        selection: $selectedLibrary) {
                        libraryRowBuilder(library: library)
                    }
                }.onDelete(perform: { indexSet in
                    let deletedLibraryIds = indexSet.map { libraryList[$0] }
                    deletedLibraryIds.forEach { libraryId in
                        self.modelData.hideLibrary(libraryId: libraryId)
                        
                        guard self.modelData.librarySyncStatus[libraryId]?.isSync != true else { return }
                        
                        guard let library = self.modelData.calibreLibraries[libraryId]
                        else { return }
                        
                        self.modelData.calibreUpdatedSubject.send(.library(library))
                        
                        Task {
                            await self.modelData.removeLibrary(library: library)
                        }
                    }
                    updateLibraryList()
                })
            }
            
            NavigationLink(
                destination: libraryRestoreHiddenView(),
                isActive: $libraryRestoreListActive,
                label: {
                    Text("Restore Hidden Libraries")
                }
            ).disabled(
                modelData.calibreLibraries
                    .filter { $0.value.server.id == server.id }
                    .allSatisfy { $0.value.hidden == false }
            )
        }
        .navigationTitle(server.name)
        .onAppear() {
            updateLibraryList()
        }
        .onChange(of: modelData.calibreLibraries, perform: { value in
            updateLibraryList()
        })
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    modelData.removeDeleteBooksFromServer(server: server)
                }) {
                    Image(systemName: "xmark.bin")
                }.disabled(
                    modelData.librarySyncStatus.filter {
                        $0.value.library.server.id == server.id && $0.value.del.count > 0
                    }.isEmpty
                )
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    modelData.probeServersReachability(with: [server.id], updateLibrary: true, autoUpdateOnly: true, incremental: false)
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
    private func librarySectionHeader() -> some View {
        HStack {
            Text("Libraries")
            Spacer()
            if modelData.librarySyncStatus.filter({
                $0.value.library.server.id == server.id
            }).allSatisfy({ $1.isSync == false }) == false {
                ProgressView()
            }
        }
    }
    
    @ViewBuilder
    private func libraryEntryDestination(library: CalibreLibrary) -> some View {
        if let libraryRealm = modelData.realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id) {
            LibraryDetailView(
                library: library,
                libraryRealm: libraryRealm
            ).navigationTitle(library.name)
            .onDisappear {
                var updatedLibrary = library
                
                if let helper = libraryRealm.pluginDSReaderHelper {
                    updatedLibrary.pluginColumns[CalibreLibrary.PLUGIN_DSREADER_HELPER] = CalibreLibraryDSReaderHelper(value: helper)
                }
                
                if let position = libraryRealm.pluginReadingPosition {
                    let copy = CalibreLibraryReadingPosition(value: position)
                    if library.pluginReadingPosition?._isEnabled != copy._isEnabled ||
                        library.pluginReadingPosition?.readingPositionCN != copy.readingPositionCN {
                        copy._isOverride = true
                    }
                    updatedLibrary.pluginColumns[CalibreLibrary.PLUGIN_READING_POSITION] = copy
                }
                
                if let dict = libraryRealm.pluginDictionaryViewer {
                    let copy = CalibreLibraryDictionaryViewer(value: dict)
                    if library.pluginDictionaryViewer?._isEnabled != copy._isEnabled ||
                        library.pluginDictionaryViewer?.readingPositionCN != copy.readingPositionCN {
                        copy._isOverride = true
                    }
                    updatedLibrary.pluginColumns[CalibreLibrary.PLUGIN_DICTIONARY_VIEWER] = copy
                }
                
                if let sync = libraryRealm.pluginGoodreadsSync {
                    let copy = CalibreLibraryGoodreadsSync(value: sync)
                    if library.pluginGoodreadsSync?.profileName != copy.profileName ||
                       library.pluginGoodreadsSync?.tagsColumnName != copy.tagsColumnName ||
                       library.pluginGoodreadsSync?.ratingColumnName != copy.ratingColumnName ||
                       library.pluginGoodreadsSync?.dateReadColumnName != copy.dateReadColumnName ||
                       library.pluginGoodreadsSync?.reviewColumnName != copy.reviewColumnName ||
                       library.pluginGoodreadsSync?.readingProgressColumnName != copy.readingProgressColumnName ||
                       library.pluginGoodreadsSync?._isEnabled != copy._isEnabled {
                        copy._isOverride = true
                    }
                    updatedLibrary.pluginColumns[CalibreLibrary.PLUGIN_GOODREADS_SYNC] = copy
                }
                
                if let pages = libraryRealm.pluginCountPages {
                    let copy = CalibreLibraryCountPages(value: pages)
                    if library.pluginCountPages?.pageCountCN != copy.pageCountCN ||
                        library.pluginCountPages?.wordCountCN != copy.wordCountCN ||
                        library.pluginCountPages?.fleschReadingEaseCN != copy.fleschReadingEaseCN ||
                        library.pluginCountPages?.fleschKincaidGradeCN != copy.fleschKincaidGradeCN ||
                        library.pluginCountPages?.gunningFogIndexCN != copy.gunningFogIndexCN ||
                        library.pluginCountPages?._isEnabled != copy._isEnabled {
                        copy._isOverride = true
                    }
                    updatedLibrary.pluginColumns[CalibreLibrary.PLUGIN_COUNT_PAGES] = copy
                }
                
                modelData.calibreLibraries[library.id] = updatedLibrary
            }
        }
    }
    
    @ViewBuilder
    private func libraryRestoreHiddenView() -> some View {
        List(selection: $libraryRestoreListSelection) {
            ForEach(
                modelData.calibreLibraries.filter { $0.value.hidden && $0.value.server.id == server.id }.map{$0.value}.sorted{$0.id < $1.id},
                id: \.id
            ) { library in
                Text(library.name)
                    .tag(library.id)
            }
        }
        .navigationTitle(Text("Restore Hidden Libraries"))
        .environment(\.editMode, $libraryRestoreListEditMode)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    libraryRestoreListSelection.forEach {
                        modelData.restoreLibrary(libraryId: $0)
                        if let library =  self.modelData.calibreLibraries[$0],
                           library.discoverable {
                            self.modelData.calibreUpdatedSubject.send(.library(library))
                        }
                    }
                    updater += 1
                    libraryRestoreListActive.toggle()
                }) {
                    Image(systemName: "checkmark.circle")
                }.disabled(libraryRestoreListSelection.isEmpty)
            }
        }
        .onAppear {
            libraryRestoreListSelection.removeAll()
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
                    .foregroundColor(.gray)
            }
            if library.discoverable {
                Image(systemName: "eye.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "eye.slash.fill")
                    .foregroundColor(.gray)
            }
                
            Text(library.name)
            
            Spacer()
            VStack(alignment: .trailing) {
                if let cnt = modelData.librarySyncStatus[library.id]?.cnt {
                    Text("\(cnt) books")
                } else if let msg = modelData.librarySyncStatus[library.id]?.msg {
                    Text("processing\n\(msg)")
                } else if modelData.librarySyncStatus[library.id]?.isSync == true {
                    Text("processing ...")
                }
                if modelData.librarySyncStatus[library.id]?.isError == true {
                    Text(modelData.librarySyncStatus[library.id]?.msg ?? "Status Unknown")
                } else if let cnt = modelData.librarySyncStatus[library.id]?.cnt,
                          let upd = modelData.librarySyncStatus[library.id]?.upd {
                    if upd.count > 0, cnt > upd.count {
                        if modelData.librarySyncStatus[library.id]?.isUpd == true {
                            Text("Pulling book info, \(upd.count) to go")
                        } else {
                            Text("\(upd.count) entries not up to date")
                        }
                    } else if let del = modelData.librarySyncStatus[library.id]?.del, del.count > 0 {
                        Text("\(del.count) entries deleted from server")
                            .foregroundColor(.red)
                    }
                }
                else if modelData.librarySyncStatus[library.id]?.isSync == false {
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

    private func updateLibraryList() {
        libraryList = modelData.calibreLibraries.values.filter{ library in
            library.server.id == server.id && library.hidden == false
        }
        .sorted{ $0.name < $1.name }
        .map { $0.id }
        
    }
    
}

struct ServerDetailView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var server = modelData.calibreServers.values.first ?? .init(uuid: .init(), name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default")
    
    static var previews: some View {
        NavigationView {
            ServerDetailView(server: $server)
                .environmentObject(modelData)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
