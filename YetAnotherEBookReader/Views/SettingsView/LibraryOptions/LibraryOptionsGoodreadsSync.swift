//
//  LibraryOptionsGoodreadsSYnc.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

struct LibraryOptionsGoodreadsSync: View {
    let library: CalibreLibrary

    @Binding var goodreadsSync: CalibreLibraryGoodreadsSync
//    @Binding var enableGoodreadsSync: Bool
//    @Binding var goodreadsSyncProfileName: String
//    @Binding var isDefaultGoodreadsSync: Bool
//
//    @State var tagsColumnName: String = "do not use"
//    @State var ratingColumnName: String = "do not use"
//    @State var dateReadColumnName: String = "do not use"
//    @State var reviewColumnName: String = "do not use"
//    @State var readingProgressColumnName: String = "do not use"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Goodreads Sync", isOn: $goodreadsSync.isEnabled)
            
            Group {
                VStack(spacing: 4) {
                    HStack {
                        Text("Profile:").padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0))
                        TextField("Name", text: $goodreadsSync.profileName)
                            .keyboardType(.alphabet)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .border(Color(UIColor.separator))
                    }
                    Text("This is a Work-in-Progress, please stay tuned!")
                        .font(.caption)
                }   //ends profile
                
                Text("Synchronisable Custom Columns")
                    .font(.title3)
                    .padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                VStack(spacing: 8) {
                    HStack {
                        Text("Tags: ")
                        Spacer()
                        Picker(goodreadsSync.tagsColumnName, selection: $goodreadsSync.tagsColumnName) {
                            ForEach(library.customColumnInfoMultiTextKeys.reduce(into: ["do not use"]) { $0.append($1) }, id: \.self) {
                                Text($0)
                            }
                        }.pickerStyle(MenuPickerStyle()).frame(minWidth: 100)
                    }
                    HStack {
                        Text("Rating: ")
                        Spacer()
                        Picker(goodreadsSync.ratingColumnName, selection: $goodreadsSync.ratingColumnName) {
                            ForEach(library.customColumnInfoRatingKeys.reduce(into: ["do not use"]) { $0.append($1) }, id: \.self) {
                                Text($0)
                            }
                        }.pickerStyle(MenuPickerStyle()).frame(minWidth: 100)
                    }
                    HStack {
                        Text("Date read: ")
                        Spacer()
                        Picker(goodreadsSync.dateReadColumnName, selection: $goodreadsSync.dateReadColumnName) {
                            ForEach(library.customColumnInfoDateKeys.reduce(into: ["do not use"]) { $0.append($1) }, id: \.self) {
                                Text($0)
                            }
                        }.pickerStyle(MenuPickerStyle()).frame(minWidth: 100)
                    }
                    HStack {
                        Text("Review text: ")
                        Spacer()
                        Picker(goodreadsSync.reviewColumnName, selection: $goodreadsSync.reviewColumnName) {
                            ForEach(library.customColumnInfoCommentKeys.reduce(into: ["do not use"]) { $0.append($1) }, id: \.self) {
                                Text($0)
                            }
                        }.pickerStyle(MenuPickerStyle()).frame(minWidth: 100)
                    }
                    HStack {
                        Text("Reading progress: ")
                        Spacer()
                        Picker(goodreadsSync.readingProgressColumnName, selection: $goodreadsSync.readingProgressColumnName) {
                            ForEach(library.customColumnInfoNumberKeys.reduce(into: ["do not use"]) { $0.append($1) }, id: \.self) {
                                Text($0)
                            }
                        }.pickerStyle(MenuPickerStyle()).frame(minWidth: 100)
                    }
                }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                
                Toggle("Set as Server-wide Default", isOn: $goodreadsSync.isDefault)
                
            }   //ends Group
            .disabled(!goodreadsSync.isEnabled)
        }   //ends VStack
    }   //ends body
}

struct LibraryOptionsGoodreadsSYnc_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")

//    @State static private var enableGoodreadsSync = false
//    @State static private var goodreadsSyncProfileName = ""
//    @State static private var isDefaultGoodreadsSync = false
    @State static private var goodreadsSync = CalibreLibraryGoodreadsSync()
    
    static var previews: some View {
        LibraryOptionsGoodreadsSync(library: library, goodreadsSync: $goodreadsSync)
    }
}
