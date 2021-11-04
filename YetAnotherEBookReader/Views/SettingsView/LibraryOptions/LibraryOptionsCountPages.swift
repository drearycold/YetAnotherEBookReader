//
//  LibraryOptionsCountPages.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/4.
//

import SwiftUI

struct LibraryOptionsCountPages: View {
    let library: CalibreLibrary

    @Binding var countPages: CalibreLibraryCountPages

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable", isOn: $countPages._isEnabled)
                .font(.title2)
            
            Group {
                Text("Plugin Custom Columns")
                    .font(.title2)
                    .padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                VStack(spacing: 8) {

                    columnPickerRowView(
                        label: "Page Count",
                        selection: $countPages.pageCountCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Word Count",
                        selection: $countPages.wordCountCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Flesch Reading Ease",
                        selection: $countPages.fleschReadingEaseCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Flesch-Kincaid Grade",
                        selection: $countPages.fleschKincaidGradeCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Gunning Fog Index",
                        selection: $countPages.gunningFogIndexCN,
                        source: library.customColumnInfoNumberKeys)
                    
                }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                
                Divider()
                
                Toggle("Set as Server-wide Default", isOn: $countPages._isDefault)
                
            }   //ends Group
            .disabled(!countPages.isEnabled())
        }   //ends VStack
    }
    
    
    @ViewBuilder
    private func columnPickerRowView(label: String, selection: Binding<String>, source: [CalibreCustomColumnInfo]) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker(source.first { "#" + $0.label == selection.wrappedValue }?.name ?? "not set",
                selection: selection) {
                ForEach(source.reduce(
                    into: [("not set", "#")]) {
                    $0.append(($1.name, "#" + $1.label))
                }, id: \.1) {    //(name, label), prepend label with "#"
                    Text("\($0) (\($1))").tag($1)
                }
            }.pickerStyle(MenuPickerStyle()).frame(minWidth: 150, alignment: .leading)
        }
    }
}

struct LibraryOptionsCountPages_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")

    @State static private var countPages = CalibreLibraryCountPages()

    static var previews: some View {
        LibraryOptionsCountPages(library: library, countPages: $countPages)
    }
}
