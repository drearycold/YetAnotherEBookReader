//
//  ShelfLegacySectionHeader.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-27.
//

import SwiftUI

public struct ShelfLegacySectionHeader: View {
    public let title: String
    
    public init(title: String) {
        self.title = title
    }
    
    public var body: some View {
        ZStack {
            Image("header")
                .resizable()
                .frame(height: 32)
            
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: Color(red: 0.25, green: 0.15, blue: 0.08), radius: 0, x: 0, y: 1)
                .padding(.horizontal, 8)
                .lineLimit(1)
        }
        .frame(height: 32)
    }
}
