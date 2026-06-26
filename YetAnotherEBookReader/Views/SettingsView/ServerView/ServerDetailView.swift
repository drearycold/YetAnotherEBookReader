//
//  ServerDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2022/2/14.
//

import SwiftUI
import Combine

struct ServerDetailView: View {
    @EnvironmentObject var container: AppContainer

    @Binding var server: CalibreServer
    @StateObject private var viewModel: ServerViewModel
    
    @State private var modServerActive = false
    @State private var dshelperActive = false
    @State private var updater = 0
    
    init(server: Binding<CalibreServer>) {
        self._server = server
        self._viewModel = StateObject(wrappedValue: ServerViewModel(container: AppContainer.shared ?? AppContainer(), server: server.wrappedValue))
    }
    
    var body: some View {
        Form {
            Section(header: Text("Options")) {
                NavigationLink(
                    destination: AddModServerView(
                        viewModel: viewModel,
                        server: Binding<CalibreServer?>(
                            get: { server },
                            set: { if let val = $0 { server = val } }
                        ),
                        isActive: $modServerActive
                    )
                        .navigationTitle("Modify: \(server.name)"),
                    isActive: $modServerActive,
                    label: {
                        Text("Modify Configuration")
                    }
                )
                .isDetailLink(false)
                
                NavigationLink(
                    destination: ServerOptionsDSReaderHelper(viewModel: viewModel, server: $server, updater: $updater),
                    isActive: $dshelperActive,
                    label: {
                        Text("DSReader Helper")
                    }
                )
                .isDetailLink(false)
            }
            
            Section(header: librarySectionHeader()) {
                ForEach(viewModel.libraryList.compactMap { container.libraryManager.calibreLibraries[$0] }, id: \.self) { library in
                    NavigationLink(
                        destination: libraryEntryDestination(library: library),
                        tag: library.id,
                        selection: $viewModel.selectedLibrary) {
                        libraryRowBuilder(library: library)
                    }
                }.onDelete(perform: { indexSet in
                    viewModel.deleteLibrary(at: indexSet)
                })
            }

            NavigationLink(
                destination: libraryRestoreHiddenView(),
                isActive: $viewModel.libraryRestoreListActive,
                label: {
                    Text("Restore Hidden Libraries")
                }
            ).disabled(
                container.libraryManager.calibreLibraries
                    .filter { $0.value.server.id == server.id }
                    .allSatisfy { $0.value.hidden == false }
            )
        }
        .navigationTitle(server.name)
        .onAppear() {
            viewModel.updateLibraryList()
        }
        .onChange(of: container.libraryManager.calibreLibraries, perform: { _ in
            viewModel.updateLibraryList()
        })
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    viewModel.removeDeleteBooksFromServer(server: server)
                }) {
                    Image(systemName: "xmark.bin")
                }.disabled(
                    container.libraryManager.librarySyncStatus.filter {
                        $0.value.library.server.id == server.id && $0.value.del.count > 0
                    }.isEmpty
                )
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    viewModel.probeReachability(server: server)
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }.disabled(viewModel.syncingLibrary)
            }
        }
    }

    @ViewBuilder
    private func librarySectionHeader() -> some View {
        HStack {
            Text("Libraries")
            Spacer()
            if container.libraryManager.librarySyncStatus.filter({
                $0.value.library.server.id == server.id
            }).allSatisfy({ $1.isSync == false }) == false {
                ProgressView()
            }
        }
    }
    
    @ViewBuilder
    private func libraryEntryDestination(library: CalibreLibrary) -> some View {
        LibraryDetailView(
            container: container,
            library: library
        ).navigationTitle(library.name)
    }
    
    @ViewBuilder
    private func libraryRestoreHiddenView() -> some View {
        List(selection: $viewModel.libraryRestoreListSelection) {
            ForEach(
                container.libraryManager.calibreLibraries.filter { $0.value.hidden && $0.value.server.id == server.id }.map{$0.value}.sorted{$0.id < $1.id},
                id: \.id
            ) { library in
                Text(library.name)
                    .tag(library.id)
            }
        }
        .navigationTitle(Text("Restore Hidden Libraries"))
        .environment(\.editMode, .constant(.active))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    viewModel.restoreSelectedLibraries(updater: $updater)
                }) {
                    Image(systemName: "checkmark.circle")
                }.disabled(viewModel.libraryRestoreListSelection.isEmpty)
            }
        }
        .onAppear {
            viewModel.libraryRestoreListSelection.removeAll()
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
                if let status = container.libraryManager.librarySyncStatus[library.id] {
                    if status.isSync {
                        if let msg = status.msg {
                            Text("processing\n\(msg)")
                        } else {
                            Text("processing ...")
                        }
                    } else if status.isError {
                        Text(status.msg ?? "Status Unknown")
                    } else {
                        // Success state or finished syncing
                        if let cnt = status.cnt {
                            Text("\(cnt) books")
                        } else if let msg = status.msg {
                            Text(msg)
                        }

                        if status.isUpd && status.upd.count > 0 {
                            Text("Pulling book info, \(status.upd.count) to go")
                        } else if status.upd.count > 0 {
                            Text("\(status.upd.count) entries not up to date")
                        }

                        if status.del.count > 0 {
                            Text("\(status.del.count) entries deleted from server")
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Text("Insufficient Info")
                }
            }.font(.caption2)
            ZStack {
                if container.libraryManager.librarySyncStatus[library.id]?.isSync ?? false {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .hidden()
                }

                if let status = container.libraryManager.librarySyncStatus[library.id],
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

                if container.libraryManager.librarySyncStatus[library.id]?.isSync == false,
                   container.libraryManager.librarySyncStatus[library.id]?.isError == true {
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
    static private var container = AppContainer(mock: true)

    @State static private var server = container.serverManager.calibreServers.values.first ?? .init(uuid: .init(), name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default")
    
    static var previews: some View {
        NavigationView {
            ServerDetailView(server: $server)
                .environmentObject(container)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
