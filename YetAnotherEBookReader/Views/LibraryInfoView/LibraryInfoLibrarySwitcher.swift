//
//  LibraryInfoLibrarySwitcher.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/16.
//

import SwiftUI

struct LibraryInfoLibrarySwitcher: View {
    @EnvironmentObject var modelData: ModelData

    @State private var calibreServerId = ""
    @State private var calibreServerLibraryId = "Undetermined"
    
    @Binding var presenting: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            Picker("Switch Server", selection: $calibreServerId) {
                ForEach(modelData.calibreServers.values.sorted(by: { (lhs, rhs) -> Bool in
                    lhs.id < rhs.id
                }), id: \.self) { server in
                    Text(server.id).tag(server.id)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            Text("\(calibreServerId)")

            Picker("Switch Library", selection: $calibreServerLibraryId) {
                ForEach(modelData.calibreLibraries.values.filter({ (library) -> Bool in
                    library.server.id == calibreServerId
                }).sorted(by: { (lhs, rhs) -> Bool in
                    lhs.name < rhs.name
                })) { library in
                    Text(library.name).tag(library.id)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            Text("\(modelData.calibreLibraries[calibreServerLibraryId]?.name ?? "")")
            
            HStack(alignment: .center, spacing: 24) {
                Button(action: {
                    presenting = false
                    if modelData.currentCalibreServerId != calibreServerId {
                        modelData.currentCalibreServerId = calibreServerId
                    }
                    if modelData.currentCalibreLibraryId != calibreServerLibraryId {
                        modelData.currentCalibreLibraryId = calibreServerLibraryId
                    }
                }) {
                    Text("OK")
                }
                Button(action: {
                    presenting = false
                }) {
                    Text("Cancel")
                }
            }
        }
        .onAppear() {
            calibreServerId = modelData.currentCalibreServerId
            calibreServerLibraryId = modelData.currentCalibreLibraryId
        }
        .padding()
    }
}

//struct LibraryInfoLibrarySwitcher_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoLibrarySwitcher()
//    }
//}
