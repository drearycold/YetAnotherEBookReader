//
//  LibraryOptionsReadingPosition.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

struct LibraryOptionsReadingPosition: View {
    let library: CalibreLibrary
    @Binding var enableStoreReadingPosition: Bool
    @Binding var storeReadingPositionColumnName: String
    @Binding var isDefaultReadingPosition: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Store Reading Position in Custom Column", isOn: $enableStoreReadingPosition)

            Text("""
                Therefore reading positions can be synced between devices.
                Please add a custom column of type \"Long text\" on calibre server.
                If there are multiple users, it's better to add a unique column for each user.
                Defaults to #read_pos(_username).
                """)
                .font(.callout)
            
            if library.server.username.isEmpty {
                Text("Also note that server defaults to read-only mode when user authentication is not required, so please allow un-authenticated connection to make changes (\"Advanced\" tab in \"Sharing over the net\")")
                    .font(.caption)
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Current Column: \(storeReadingPositionColumnName)")
                    Spacer()
                    if library.customColumnInfos[storeReadingPositionColumnName.trimmingCharacters(in: CharacterSet(["#"]))] == nil {
                        Text("unavailable").font(.caption).foregroundColor(.red)
                    }
                }
                HStack {
                    Spacer()
                    Picker("Pick another Column", selection: $storeReadingPositionColumnName) {
                        ForEach(library.customColumnInfos.keys.map{"#" + $0}.sorted{$0 < $1}, id: \.self) {
                            Text($0)
                        }
                    }.pickerStyle(MenuPickerStyle())
                    
                }
                
                Toggle("Set as Server-wide Default", isOn: $isDefaultReadingPosition)
                
            }
            .disabled(!enableStoreReadingPosition)
        }
    }
}

struct LibraryOptionsReadingPosition_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")
    @State static private var enableStoreReadingPosition = false
    @State static private var storeReadingPositionColumnName = ""
    @State static private var isDefaultReadingPosition = false
    
    static var previews: some View {
        LibraryOptionsReadingPosition(library: library, enableStoreReadingPosition: $enableStoreReadingPosition, storeReadingPositionColumnName: $storeReadingPositionColumnName, isDefaultReadingPosition: $isDefaultReadingPosition)
    }
}
