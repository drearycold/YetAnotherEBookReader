//
//  PlainShelfUI.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/2/4.
//

import Foundation
import SwiftUI

struct SectionShelfUI: UIViewControllerRepresentable {
    @EnvironmentObject var modelData: ModelData

    func makeUIViewController(context: Context) -> UINavigationController {
        let shelfController = SectionShelfController()
        shelfController.modelData = modelData
        
        let navController = UINavigationController(rootViewController: shelfController)
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
//        uiViewController.resizeSubviews(to: uiViewController.view.frame.size, to: uiViewController.traitCollection)
//        uiViewController.updateBookModel(reload: true)
//        uiViewController.reloadBookModel()
    }
    
}
