//
//  PlainShelfUI.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/2/4.
//

import Foundation
import SwiftUI

struct PlainShelfUI: UIViewControllerRepresentable {
    @EnvironmentObject var modelData: ModelData

    func makeUIViewController(context: Context) -> PlainShelfController {
        let shelfController = PlainShelfController()
        shelfController.modelData = modelData
        return shelfController
    }
    
    func updateUIViewController(_ uiView: PlainShelfController, context: Context) {
        uiView.updateBookModel()
    }
    
}
