//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.appContainer) var container
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var addServerEditor: ServerConnectionEditorViewModel
    @StateObject private var statisticsViewModel: ReadingStatisticsViewModel
    
    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _statisticsViewModel = StateObject(wrappedValue: ReadingStatisticsViewModel(container: viewModel.container))
        _addServerEditor = StateObject(wrappedValue: ServerConnectionEditorViewModel(container: viewModel.container, mode: .add))
    }
    
    var body: some View {
        Form {
            Section(header: HStack {
                Text("Servers")
                Spacer()
                if let serverListDelete = viewModel.serverListDelete {
                    Text("Removing \(serverListDelete.name)")
                    ProgressView().progressViewStyle(CircularProgressViewStyle())
                } else if viewModel.isRefreshing {
                    Text("Refreshing")
                    ProgressView().progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("")
                    ProgressView().progressViewStyle(CircularProgressViewStyle()).hidden()
                }
            }) {
                NavigationLink(
                    destination: AddModServerView(
                        viewModel: addServerEditor,
                        onFinish: { viewModel.addServerActive = false }
                    )
                    .navigationTitle("Add Server"),
                    isActive: $viewModel.addServerActive
                ) {
                    Text("Connect to a new server")
                }
                
                ForEach(viewModel.serverList, id: \.id) { server in
                    let state = viewModel.rowState(for: server)
                    Button {
                        viewModel.openServerDetail(server.id)
                    } label: {
                        HStack {
                            serverRowBuilder(server: server, state: state)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(server.name == "UI Test Server" ? "settings.server.ui-test" : "settings.server.\(server.id)")
                }
                .onDelete(perform: { indexSet in
                    guard let index = indexSet.first else { return }
                    viewModel.stageServerDeletion(at: index)
                })
                .alert(item: $viewModel.alertItem) { item in
                    if item.id == "DelServer" {
                        return Alert(
                            title: Text("Remove Server"),
                            message: Text("Will Remove Cached Libraries and Books from Reader, Everything on Server will Stay Intact"),
                            primaryButton: .destructive(Text("Confirm")) {
                                viewModel.confirmDeleteServer()
                            },
                            secondaryButton: .cancel {
                                viewModel.cancelServerDeletion()
                            }
                        )
                    }
                    return Alert(title: Text("Error"), message: Text(item.id + "\n" + (item.msg ?? "")), dismissButton: .cancel() {
                        item.action?()
                    })
                }
            }
            .disabled(viewModel.serverListDelete != nil)
            
            Section(header: Text("More")) {
                NavigationLink("Readers Options", destination: ReaderOptionsView())
                NavigationLink("Reading Statistics", destination: ReadingStatisticsView(viewModel: statisticsViewModel))
                    .accessibilityIdentifier("settings.reading-statistics")
                NavigationLink("Activity Logs", destination: LazyView(ActivityList(viewModel: ActivityListViewModel(repository: container.activityLogRepository))))
            }
            
            Section(
                header: Text("Support"),
                footer: HStack {
                    Spacer()
                    Text("Version \(YabrAppInfo.shared.version)")
                    Text("Build \(YabrAppInfo.shared.build)")
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.gray)
            ) {
                NavigationLink("Support", destination: SupportInfoView())
                NavigationLink("About calibre Server", destination: ServerCalibreIntroView().frame(maxWidth: 600))
                NavigationLink("About DSReader", destination: AppInfoView())
            }
        }
        .background(serverDetailLink)
        .navigationTitle("Settings")
        .accessibilityIdentifier("screen.settings")
        .toolbar {
            ToolbarItem {
                Button(action:{
                    viewModel.refreshServers()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .onAppear() {
            viewModel.updateServerList()
        }
        .onChange(of: viewModel.addServerActive) { active in
            if !active { addServerEditor.endEditing() }
        }
        .onChange(of: viewModel.serverListDelete, perform: { value in
            viewModel.updateServerList()
        })
    }

    private var serverDetailLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { viewModel.selectedServer != nil },
                set: { if !$0 { viewModel.dismissServerDetail() } }
            )
        ) {
            if let serverID = viewModel.displayedServerID {
                ServerDetailView(
                    container: viewModel.container,
                    serverID: serverID
                )
                .id(serverID)
            }
        } label: {
            EmptyView()
        }
        .isDetailLink(false)
        .hidden()
    }
    
    @ViewBuilder
    private func serverRowBuilder(server: CalibreServer, state: SettingsViewModel.ServerRowState) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(server.name)")
                Spacer()
                if state.hasDSReaderHelper {
                    Image("logo_1024")
                        .resizable()
                        .frame(width: 16, height: 16, alignment: .center)
                }
                
                if let reachable = state.isLocalReachable {
                    Image(
                        systemName: reachable ? "flag.circle" : "flag.slash.circle"
                    ).foregroundColor(reachable ? .green : .red)
                }
                
                if let reachable = state.isPublicReachable {
                    Image(
                        systemName: reachable ? "flag" : "flag.slash"
                    ).foregroundColor(reachable ? .green : .red)
                }
                
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if server.isLocal == false {
                        Text("\(state.libraryCount) libraries")
                    }
                    
                    HStack(spacing: 4) {
                        Text("Location:")
                        Text(state.locationString)
                    }
                }
                
                Spacer()
                
                if state.processingCount > 0 {
                    Text("\(state.processingCount) processing")
                } else if let serverInfoText = state.serverInfoText {
                    Text(serverInfoText)
                        .foregroundColor(state.isServerError ? .red : .primary)
                }
            }
            .font(.caption)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static private var container = AppContainer()

    static var previews: some View {
        NavigationView {
            SettingsView(viewModel: SettingsViewModel(container: container))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environment(\.appContainer, container)
    }
}
