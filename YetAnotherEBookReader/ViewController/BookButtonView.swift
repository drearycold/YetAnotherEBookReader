//
//  ReaderView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/26.
//

import Foundation
import UIKit
import SwiftUI

struct BookButtonView: UIViewRepresentable {
    let button = UIButton(type: .system)

    func makeUIView(context: Context) -> UIView {
        //let view = UIView()
        
        button.setTitle("TEST", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.sizeToFit()
        
        //view.addSubview(button)
        //return view
        
        return button
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
}
