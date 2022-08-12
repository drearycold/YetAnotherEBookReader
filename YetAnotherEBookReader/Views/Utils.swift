//
//  Utils.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/4.
//

import SwiftUI
import Foundation

struct AlertItem : Identifiable, Equatable {
    static func == (lhs: AlertItem, rhs: AlertItem) -> Bool {
        lhs.id == rhs.id
    }

    var id: String
    var msg: String?
    var action: (() -> Void)?
}

protocol AlertDelegate {
    func alert(alertItem: AlertItem)
    func alert(msg: String)
}

extension AlertDelegate {
    func alert(msg: String) {
        self.alert(
            alertItem: AlertItem(
                id: "Alert",
                msg: msg
            )
        )
    }
}

extension UIApplication {
    
    var keyWindow: UIWindow? {
        // Get connected scenes
        return UIApplication.shared.connectedScenes
            // Keep only active scenes, onscreen and visible to the user
            .filter { $0.activationState == .foregroundActive }
            // Keep only the first `UIWindowScene`
            .first(where: { $0 is UIWindowScene })
            // Get its associated windows
            .flatMap({ $0 as? UIWindowScene })?.windows
            // Finally, keep only the key window
            .first(where: \.isKeyWindow)
    }
    
}
