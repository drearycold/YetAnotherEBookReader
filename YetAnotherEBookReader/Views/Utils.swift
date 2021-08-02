//
//  Utils.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/4.
//

import SwiftUI
import Foundation

struct AlertItem : Identifiable {
    var id: String
    var msg: String?
    var action: (() -> Void)?
}

protocol AlertDelegate {
    func alert(alertItem: AlertItem)
}
