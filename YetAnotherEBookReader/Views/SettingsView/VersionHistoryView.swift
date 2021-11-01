//
//  VersionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//

import SwiftUI

struct VersionHistoryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Version 0.2.0").font(.title2)
                Text("""
                    TODO
                    """)
                
                Text("Version 0.1.0").font(.title2)
                Text("""
                    Initial Release.
                    
                    """)
                
            }
        }
        
    }
}

struct VersionHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        VersionHistoryView()
    }
}
