//
//  LibraryOptionsReadingPosition.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

struct LibraryOptionsReadingPosition: View {
    let library: CalibreLibrary
    
    @Binding var readingPosition: CalibreLibraryReadingPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Store Reading Position in Custom Column", isOn: $readingPosition._isEnabled)

            Text("""
                Therefore reading positions can be synced between devices.
                Please add a custom column of type \"Long text, like comments\" on calibre server.
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
                    Text("Current Column: \(readingPosition.readingPositionCN)")
                    Spacer()
                    if let columnInfo = library.customColumnInfos[readingPosition.readingPositionCN.trimmingCharacters(in: CharacterSet(["#"]))] {
                        Text("datatype \(columnInfo.datatype)").font(.caption)
                    } else {
                        Text("column unavailable").font(.caption).foregroundColor(.red)
                    }
                }
                HStack {
                    Spacer()
                    Picker("Pick another Column", selection: $readingPosition.readingPositionCN) {
                        ForEach(library.customColumnInfos.filter{ $1.datatype == "comments" }.keys.map{"#" + $0}.sorted{$0 < $1}, id: \.self) {
                            Text($0)
                        }
                    }.pickerStyle(MenuPickerStyle())
                }
                
                Toggle("Set as Server-wide Default", isOn: $readingPosition._isDefault)
                
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
