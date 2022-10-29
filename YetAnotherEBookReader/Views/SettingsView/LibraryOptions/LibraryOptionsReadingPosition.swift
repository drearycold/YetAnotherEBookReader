//
//  LibraryOptionsReadingPosition.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

struct LibraryOptionsReadingPosition: View {
    let library: CalibreLibrary
    
    @Binding var dsreaderHelperServer: CalibreServerDSReaderHelper
    @Binding var readingPosition: CalibreLibraryReadingPosition
    @Binding var dsreaderHelperLibrary: CalibreLibraryDSReaderHelper
    @Binding var goodreadsSync: CalibreLibraryGoodreadsSync

    @State private var instructionPresenting = false
    
    var body: some View {
        Form {
            Section(
                header: Text("Reading Position Storage"),
                footer: HStack {
                    Spacer()
                    if library.customColumnInfos.filter{ $1.datatype == "comments" }.isEmpty {
                        Text("Please refresh library after adding column to server library")
                            .foregroundColor(.red)
                    }
                }) {
                Toggle("Store Reading Positions in Custom Column", isOn: $readingPosition._isEnabled)
                
                if library.customColumnInfos.filter{ $1.datatype == "comments" }.count > 0 {
                    Picker("Column Name:     \(readingPosition.readingPositionCN)", selection: $readingPosition.readingPositionCN) {
                        ForEach(library.customColumnInfoCommentsKeysFull
                                    .map{ ($0.name, "#" + $0.label) }, id: \.1) {
                            Text("\($1)\n\($0)").tag($1)
                        }
                    }.pickerStyle(MenuPickerStyle())
                    .disabled(!readingPosition.isEnabled())
                } else {
                    Text("Column Name:     No Available Column")
                }
            }
            
            Section(
                header: Text("Goodreads Sync"),
                footer: HStack {
                    if !(dsreaderHelperServer.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.goodreadsSyncEnabled ?? false) {
                        Spacer()
                        
                        Text("Plugin not available").foregroundColor(.red)
                    }
                }
            ) {
                Toggle("Enable Automation", isOn: $dsreaderHelperLibrary._isEnabled)
                
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
                            Text("Profile Name:     Empty Profile List")
                        }
                    }
                    
                    Toggle("Auto Update Reading Progress", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsProgress)
                    
                    Toggle("Auto Update Book Shelf", isOn: $dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf)
                }
                .disabled( !dsreaderHelperLibrary.isEnabled() )
            }
            .disabled(
                !(dsreaderHelperServer.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.goodreadsSyncEnabled ?? false)
            )
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action:{
                    instructionPresenting = true
                }) {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $instructionPresenting) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        
                        Text("Custom Column Requirements for Storing Reading Position").font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Please add a custom column of type \"Long text, like comments\" on calibre server.")
                            
                            Text("If there are multiple users, it's better to add a unique column for each user.")
                            
                            Text("Defaults to #read_pos(_username).")
                        }
                        .lineLimit(3)
                        .font(.callout)
                        
                        if library.server.username.isEmpty {
                            Text("Also note that server defaults to read-only mode when user authentication is not required, so please allow un-authenticated connection to make changes (\"Advanced\" tab in \"Sharing over the net\")")
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action:{
                            instructionPresenting.toggle()
                        }) {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
            
        }
    }
}

struct LibraryOptionsReadingPosition_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "Default", name: "Default")
    
    @State static private var dsreaderHelperServer = CalibreServerDSReaderHelper(id: "", port: 0)

    @State static private var readingPosition = CalibreLibraryReadingPosition()
    @State static private var dsreaderHelperLibrary = CalibreLibraryDSReaderHelper()
    @State static private var goodreadsSync = CalibreLibraryGoodreadsSync()
    
    static var previews: some View {
        NavigationView {
            LibraryOptionsReadingPosition(library: library, dsreaderHelperServer: $dsreaderHelperServer, readingPosition: $readingPosition, dsreaderHelperLibrary: $dsreaderHelperLibrary, goodreadsSync: $goodreadsSync)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
