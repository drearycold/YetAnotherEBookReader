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

    func makeUIViewController(context: Context) -> UINavigationController {
        let shelfController = RecentShelfController()
        shelfController.modelData = modelData
        
        let navController = UINavigationController(rootViewController: shelfController)
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
//        uiViewController.updateBookModel()
    }
    
}
