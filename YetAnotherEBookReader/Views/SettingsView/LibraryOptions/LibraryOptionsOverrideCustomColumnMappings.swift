//
//  LibraryOptionsOverrideCustomColumnMappings.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/27.
//

import SwiftUI

struct LibraryOptionsOverrideCustomColumnMappings: View {
    let library: CalibreLibrary
    let configuration: CalibreDSReaderHelperConfiguration

    @Binding var goodreadsSync: CalibreLibraryGoodreadsSync
    @Binding var countPages: CalibreLibraryCountPages

    var body: some View {
        Form {
            LibraryOptionsGoodreadsSync(library: library, configuration: configuration, goodreadsSync: $goodreadsSync)
            
            LibraryOptionsCountPages(library: library, configuration: configuration, countPages: $countPages)
        }
    }
}

struct LibraryOptionsOverrideCustomColumnMappings_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "Default", name: "Default")

    @State static private var goodreadsSync = CalibreLibraryGoodreadsSync()
    @State static private var countPages = CalibreLibraryCountPages()
    static private var configuration = CalibreDSReaderHelperConfiguration()

    static var previews: some View {
        NavigationView {
            LibraryOptionsOverrideCustomColumnMappings(library: library, configuration: configuration, goodreadsSync: $goodreadsSync, countPages: $countPages)
        }
    }
}
