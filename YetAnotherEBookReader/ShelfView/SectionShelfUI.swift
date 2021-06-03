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

    func makeUIViewController(context: Context) -> SectionShelfController {
        let shelfController = SectionShelfController()
        shelfController.modelData = modelData
        return shelfController
    }
    
    func updateUIViewController(_ uiView: SectionShelfController, context: Context) {
        uiView.updateBookModel()
    }
    
}
