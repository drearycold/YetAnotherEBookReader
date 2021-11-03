//
//  VersionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//

import SwiftUI

struct VersionHistoryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version 0.2.0").font(.title2)
                    textLine("Tighter Integration with Goodreads Sync Plugin's Custom Columns")
                    textLine("Navigate to BookInfo/Goodreads/Douban directly from RecentShelf's Book Context Menu")
                    textLine("Activity Logs Viewer to Help Troubleshooting Network Ralated Issues")
                    textLine("Reading Statistics and Position History Viewer to Track Your Time")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version 0.1.0").font(.title2)
                    textLine("Initial Release")
                    textLine("Supports Reading EPUB/PDF/CBZ")
                    textLine("Supports Interaction with calibre Context Server")
                }
            }
        }
    }
    
    @ViewBuilder
    private func textLine(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("★")
            Text(line)
        }
    }
}

struct VersionHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        VersionHistoryView()
    }
}
