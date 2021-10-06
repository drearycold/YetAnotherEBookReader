//
//  MDictViewUIVC.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/6.
//

import Foundation
import SwiftUI

struct MDictViewUIVC: UIViewControllerRepresentable {
    
    var server: URL
    
    public init(server: URL) {
        self.server = server
    }
    
    func updateUIViewController(_ uiViewController: MDictViewContainer, context: Context) {
    }
    
    func makeUIViewController(context: Context) -> MDictViewContainer {
        let mdictView = MDictViewContainer()
        mdictView.server = server.absoluteString
        mdictView.title = "hello"
        return mdictView
    }
}
