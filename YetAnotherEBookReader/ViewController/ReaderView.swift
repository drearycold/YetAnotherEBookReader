//
//  ReaderView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/26.
//

import SwiftUI

@available(macCatalyst 14.0, *)
struct ReaderView: View {
    var body: some View {
        
        VStack {
            MyReaderViewController()
        }
        
    }
}

@available(macCatalyst 14.0, *)
struct ReaderView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderView()
    }
}
