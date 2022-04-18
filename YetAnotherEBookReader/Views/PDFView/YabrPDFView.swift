//
//  YabrPDFView.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/4/18.
//

import Foundation

import PDFKit

class YabrPDFView: PDFView {
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        print("\(#function) \(action.description)")
        if action.description == "selectAll:" {
            return false
        }
        
        return super.canPerformAction(action, withSender: sender)
    }
}
