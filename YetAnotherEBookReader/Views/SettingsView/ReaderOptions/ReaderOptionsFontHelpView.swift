//
//  ReaderOptionsFontHelpView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/1/20.
//

import SwiftUI

struct ReaderOptionsFontHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("About Custom Fonts for YabrEPUB Reader")
                    .font(.title3)
                    .bold()
                Text("Don't get limited by eBook publisher's aesthetic. \(ReaderType.YabrEPUB.rawValue) supports substituting eBook content fonts with your favorite choosing.")
                Text("You can place font files inside \"Fonts\" folder of this App or import them directly from here. They will appear in the \"Font\" tab of \(ReaderType.YabrEPUB.rawValue)'s style menu.")
                Text("Currently supports TrueType (.ttf) and OpenType (.otf).")
            }.padding()
        }
    }
}

struct ReaderOptionsFontHelpView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsFontHelpView()
    }
}
