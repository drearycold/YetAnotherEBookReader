//
//  LibraryOptionsReadingPosition.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

@available(*, deprecated)
struct LibraryOptionsReadingPosition: View {
    let library: CalibreLibrary
    
    @Binding var readingPosition: CalibreLibraryReadingPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Store Reading Positions in Server and Sync between Devices").font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Enabled", isOn: $readingPosition._isEnabled)
                
                Text("Custom Column Name: \(readingPosition.readingPositionCN)")
                
                HStack {
                    Spacer()
                    if library.customColumnInfos.filter{ $1.datatype == "comments" }.count > 0 {
                        Picker("Pick another Column", selection: $readingPosition.readingPositionCN) {
                            ForEach(library.customColumnInfos.filter{ $1.datatype == "comments" }.keys.map{"#" + $0}.sorted{$0 < $1}, id: \.self) {
                                Text($0)
                            }
                        }.pickerStyle(MenuPickerStyle())
                        .disabled(!readingPosition.isEnabled())
                    } else {
                        Text("no available column, please refresh library after adding column to calibre").font(.caption).foregroundColor(.red)
                    }
                }
                
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                
                Text("Instructions").font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Please add a custom column of type \"Long text, like comments\" on calibre server.")
                    
                    Text("If there are multiple users, it's better to add a unique column for each user.")
                    
                    Text("Defaults to #read_pos(_username).")
                }    .font(.callout)
                
                if library.server.username.isEmpty {
                    Text("Also note that server defaults to read-only mode when user authentication is not required, so please allow un-authenticated connection to make changes (\"Advanced\" tab in \"Sharing over the net\")")
                        .font(.caption)
                }
                
                Divider()
                
                Toggle("Set as Server-wide Default", isOn: $readingPosition._isDefault)
                    .font(.title3).hidden()
                
            }
            .disabled(!readingPosition.isEnabled())
        }
    }
}

struct LibraryOptionsReadingPosition_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")
    
    @State static private var readingPosition = CalibreLibraryReadingPosition()
    
    static var previews: some View {
        LibraryOptionsReadingPosition(library: library, readingPosition: $readingPosition)
    }
}
