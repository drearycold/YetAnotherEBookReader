//
//  LibraryDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2022/2/14.
//

import SwiftUI

struct LibraryDetailView: View {
    @StateObject private var viewModel: LibraryViewModel

    init(container: AppContainer, library: CalibreLibrary) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(container: container, library: library))
    }

    var body: some View {
        Form {
            Section(header: Text("Browsable")) {
                Toggle("Include in Discover", isOn: Binding(
                    get: { viewModel.discoverable },
                    set: { viewModel.setDiscoverable($0) }
                ))
                .disabled(!viewModel.discoverabilityAvailable)
                if let failure = viewModel.saveFailure {
                    Text(failure.message)
                        .accessibilityIdentifier("library.discoverability.save.failure")
                }
            }
            
            Section(header: Text("Troubleshooting")) {
                NavigationLink(
                    destination: LazyView(ActivityList(viewModel: viewModel.makeActivityListViewModel()))
                ) {
                    Text("Activity Logs")
                }
                if viewModel.errCount > 0 {
                    NavigationLink {
                        List {
                            ForEach(viewModel.failedBookIds, id: \.self) { bookId in
                                HStack {
                                    Text(bookId.description)
                                    
                                    if let title = viewModel.failedBookTitles[bookId] {
                                        Spacer()
                                        Text(title)
                                    }
                                }
                            }
                        }.navigationTitle(Text("Book IDs Failed to Sync"))
                    } label: {
                        Text("Book IDs Failed to Sync")
                    }
                }
                if viewModel.delCount > 0 {
                    NavigationLink {
                        List {
                            ForEach(viewModel.deletedBookIds, id: \.self) { bookId in
                                HStack {
                                    Text(bookId.description)
                                    
                                    if let title = viewModel.deletedBookTitles[bookId] {
                                        Spacer()
                                        Text(title)
                                    }
                                }
                            }
                        }.navigationTitle(Text("Book IDs Unavailable on Server"))
                    } label: {
                        Text("Book IDs Unavailable on Server")
                    }
                }
            }
            
            #if DEBUG
            Section {
                Button("Reset Books") {
                    viewModel.resetBooks()
                }
            } header: {
                Text("OP")
            }
            
            Section {
                Text("isSync: \(viewModel.isSync ? "true" : "false")")
                Text("isUpd: \(viewModel.isUpd ? "true" : "false")")
                Text("isError: \(viewModel.isError ? "true" : "false")")
                Text("MSG: \(viewModel.msg)")
                Text("CNT: \(viewModel.cnt)")
                Text("DEL: \(viewModel.delCount)")
                Text("ERR: \(viewModel.errCount)")
            } header: {
                Text("DEBUG")
            }
            #endif
        }
    }
}

struct LibraryDetailView_Previews: PreviewProvider {
    static private var container = AppContainer(mock: true)

    @State static private var library = container.libraryManager.calibreLibraries.values.first ?? .init(server: .init(uuid: .init(), name: "default", baseUrl: "default", hasPublicUrl: true, publicUrl: "default", hasAuth: true, username: "default", password: "default"), key: "Default", name: "Default")

    static var previews: some View {
        return NavigationView {
            LibraryDetailView(
                container: container,
                library: library
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
