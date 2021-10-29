//
//  LibraryOptionsGoodreadsSYnc.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

struct LibraryOptionsGoodreadsSync: View {
    let library: CalibreLibrary

    @Binding var enableGoodreadsSync: Bool
    @Binding var goodreadsSyncProfileName: String
    @Binding var isDefaultGoodreadsSync: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Goodreads Sync", isOn: $enableGoodreadsSync)
            
            Text("This is a Work-in-Progress, please stay tuned!")
                .font(.caption)
            
            VStack(spacing: 4) {
                HStack {
                    Text("Profile:").padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0))
                    TextField("Name", text: $goodreadsSyncProfileName)
                    .keyboardType(.alphabet)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .border(Color(UIColor.separator))
                }
                
                
                Toggle("Set as Server-wide Default", isOn: $isDefaultGoodreadsSync)
                
            }.disabled(!enableGoodreadsSync)
        }
        
    }
}

struct LibraryOptionsGoodreadsSYnc_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")

    @State static private var enableGoodreadsSync = false
    @State static private var goodreadsSyncProfileName = ""
    @State static private var isDefaultGoodreadsSync = false
    
    static var previews: some View {
        LibraryOptionsGoodreadsSync(library: library, enableGoodreadsSync: $enableGoodreadsSync, goodreadsSyncProfileName: $goodreadsSyncProfileName, isDefaultGoodreadsSync: $isDefaultGoodreadsSync)
    }
}
