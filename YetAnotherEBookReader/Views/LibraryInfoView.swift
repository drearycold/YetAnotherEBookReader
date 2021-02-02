//
//  LibraryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import SwiftUI
import CoreData

@available(macCatalyst 14.0, *)
struct LibraryInfoView: View {
    @EnvironmentObject var modelData: ModelData

    @Binding var libraryInfo: LibraryInfo
    
    var body: some View {
        NavigationView {
            List {
                ForEach(libraryInfo.libraries.indices, id: \.self) { index in
                    NavigationLink(
                        destination: LibraryView(library: $libraryInfo.libraries[index])) {
                            Text("\(libraryInfo.libraries[index].name)")
                        }
                }
            }
            .navigationBarTitle("Pick a Library")
            .navigationBarHidden(true)
        }
    }
}

@available(macCatalyst 14.0, *)
struct LibraryInfoView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    @State static private var libraryInfo = LibraryInfo()
    static var previews: some View {
        LibraryInfoView(libraryInfo: $libraryInfo)
            .environmentObject(ModelData())
    }
}
