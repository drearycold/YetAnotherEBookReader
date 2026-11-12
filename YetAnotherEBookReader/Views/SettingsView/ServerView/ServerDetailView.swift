//
//  ServerDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2022/2/14.
//

import SwiftUI

struct ServerDetailView: View {
    private let container: AppContainer
    private let onConnectionUpdate: (CalibreServer, CalibreServer) -> Void

    @StateObject private var viewModel: ServerDetailViewModel
    @StateObject private var editor: ServerConnectionEditorViewModel
    @StateObject private var helper: DSReaderHelperConfigurationViewModel
    private enum Route {
        case editor, helper, hiddenLibraries
        case library(String)
    }

    @State private var activeRoute: Route?
    @State private var displayedRoute: Route?

    init(
        container: AppContainer, serverID: String,
        onConnectionUpdate: @escaping (CalibreServer, CalibreServer) -> Void
    ) {
        self.container = container
        self.onConnectionUpdate = onConnectionUpdate
        _viewModel = StateObject(wrappedValue: .init(container: container, serverID: serverID))
        _editor = StateObject(wrappedValue: .init(container: container, mode: .edit(serverID: serverID)))
        _helper = StateObject(wrappedValue: .init(container: container, serverID: serverID))
    }

    var body: some View {
        let snapshot = viewModel.snapshot
        Form {
            if snapshot.name == nil {
                Text("This server is no longer available.")
            }
            Section(header: Text("Options")) {
                routeButton(.editor) { Text("Modify Configuration") }
                    .disabled(snapshot.name == nil)
                routeButton(.helper) { Text("DSReader Helper") }
                    .disabled(snapshot.name == nil)
            }

            Section(header: librarySectionHeader) {
                ForEach(snapshot.visible) { row in
                    routeButton(.library(row.id)) { libraryRow(row) }
                        .accessibilityIdentifier("server.detail.library.\(row.id)")
                }
                .onDelete(perform: viewModel.removeLibraries)
            }

            routeButton(.hiddenLibraries) { Text("Restore Hidden Libraries") }
                .disabled(snapshot.hidden.isEmpty)
        }
        .background(routeLink)
        .navigationTitle(snapshot.name ?? "Server")
        .onAppear { viewModel.startObserving(.detail) }
        .onDisappear { viewModel.stopObserving(.detail) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ServerDetailRefreshButton(viewModel: viewModel)
            }
        }
    }

    private func routeButton<Label: View>(_ route: Route, @ViewBuilder label: () -> Label) -> some View {
        Button {
            displayedRoute = route
            activeRoute = route
        } label: {
            HStack {
                label().frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var routeLink: some View {
        NavigationLink(
            isActive: Binding(get: { activeRoute != nil }, set: { if !$0 { dismissRoute() } })
        ) {
            switch displayedRoute {
            case .editor:
                AddModServerView(viewModel: editor, onConfirm: confirmEdit, onFinish: dismissRoute)
                    .navigationTitle("Modify: \(viewModel.snapshot.name ?? "")")
            case .helper:
                ServerOptionsDSReaderHelper(viewModel: helper)
            case .library(let id):
                libraryDestination(id: id).id(id)
            case .hiddenLibraries:
                HiddenServerLibrariesView(viewModel: viewModel, onRestore: dismissRoute)
            case nil:
                EmptyView()
            }
        } label: {
            EmptyView()
        }
        .isDetailLink(false)
        .hidden()
    }

    private func dismissRoute() {
        switch activeRoute {
        case .editor: editor.endEditing()
        case .helper: helper.closeRoute()
        case .library, .hiddenLibraries, nil: break
        }
        activeRoute = nil
    }

    private func confirmEdit(_ confirmation: ServerConnectionEditorViewModel.Confirmation) {
        guard case .edited(let original, let updated) = confirmation else { return }
        onConnectionUpdate(original, updated)
    }

    private var librarySectionHeader: some View {
        HStack {
            Text("Libraries")
            Spacer()
            if viewModel.snapshot.syncing { ProgressView() }
        }
    }

    @ViewBuilder
    private func libraryDestination(id: String) -> some View {
        if let library = viewModel.library(for: id) {
            LibraryDetailView(container: container, library: library)
                .navigationTitle(library.name)
        } else {
            Text("This library is no longer available.")
        }
    }

    private func libraryRow(_ row: ServerDetailViewModel.LibraryRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.discoverable ? "eye.fill" : "eye.slash.fill")
                .foregroundColor(row.discoverable ? .green : .gray)
            Text(row.name)
            Spacer()

            VStack(alignment: .trailing) {
                if let status = row.status {
                    if status.syncing {
                        Text(status.message.map { "processing\n\($0)" } ?? "processing ...")
                    } else if status.failed {
                        Text(status.message ?? "Status Unknown")
                    } else {
                        if let count = status.count {
                            Text("\(count) books")
                        } else if let message = status.message {
                            Text(message)
                        }
                        if status.unavailableCount > 0 {
                            Text("\(status.unavailableCount) books unavailable on server")
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text("Insufficient Info")
                }
            }
            .font(.caption2)

            ZStack {
                ProgressView()
                    .opacity(row.status?.syncing == true ? 1 : 0)
                if let status = row.status, !status.syncing {
                    if status.failed {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    } else if status.message == "Success" {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    }
                }
            }
        }
    }
}

// Hosted controls observe the live model because iOS 15 retains initial ToolbarContent values.
private struct ServerDetailRefreshButton: View {
    @ObservedObject var viewModel: ServerDetailViewModel

    var body: some View {
        Button(action: viewModel.probeReachability) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Refresh Server")
        .disabled(viewModel.snapshot.name == nil || viewModel.snapshot.probing)
    }
}

private struct HiddenServerLibrariesView: View {
    @ObservedObject var viewModel: ServerDetailViewModel
    let onRestore: () -> Void

    var body: some View {
        List(selection: $viewModel.restoreSelection) {
            ForEach(viewModel.snapshot.hidden) { row in
                Text(row.name).tag(row.id)
            }
        }
        .navigationTitle("Restore Hidden Libraries")
        .environment(\.editMode, .constant(.active))
        .onAppear {
            viewModel.restoreSelection.removeAll()
            viewModel.startObserving(.hiddenLibraries)
        }
        .onDisappear { viewModel.stopObserving(.hiddenLibraries) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RestoreServerLibrariesButton(viewModel: viewModel, onRestore: onRestore)
            }
        }
    }
}

private struct RestoreServerLibrariesButton: View {
    @ObservedObject var viewModel: ServerDetailViewModel
    let onRestore: () -> Void

    var body: some View {
        Button {
            viewModel.restoreLibraries(viewModel.restoreSelection)
            onRestore()
        } label: {
            Image(systemName: "checkmark.circle")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Restore Selected Libraries")
        .disabled(viewModel.restoreSelection.isEmpty)
    }
}

struct ServerDetailView_Previews: PreviewProvider {
    static private let container = AppContainer(mock: true)

    static var previews: some View {
        let serverID = container.serverManager.calibreServers.values.first?.id ?? CalibreServer.LocalServerUUID.uuidString
        NavigationView {
            ServerDetailView(container: container, serverID: serverID, onConnectionUpdate: { _, _ in })
        }
        .navigationViewStyle(.stack)
    }
}
