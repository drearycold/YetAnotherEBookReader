//
//  PlainShelfUI.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/2/4.
//

import Foundation
import SwiftUI

struct RecentShelfUI: UIViewControllerRepresentable {
    @EnvironmentObject var modelData: ModelData

    func makeUIViewController(context: Context) -> RecentShelfController {
        let shelfController = RecentShelfController()
        shelfController.modelData = modelData
        return shelfController
    }
    
    func updateUIViewController(_ uiViewController: RecentShelfController, context: Context) {
        uiViewController.updateBookModel()
    }
    
}
