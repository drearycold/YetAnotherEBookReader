//
//  PDFPageWithBackground.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/10.
//

import Foundation
import PDFKit

class PDFPageWithBackground : PDFPage {
    static var fillColor: CGColor? = nil   //defaults to serpia
    static let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        // Draw original content
        super.draw(with: box, to: context)
        
        guard let fillColor = PDFPageWithBackground.fillColor?.converted(to: PDFPageWithBackground.colorSpace, intent: .defaultIntent, options: nil) else { return }
        
        if PDFPageWithBackground.fillColor != CGColor(gray: 1.0, alpha: 1.0) {
            UIGraphicsPushContext(context)
            context.saveGState()
            context.setBlendMode(.darken)
            context.setFillColor(fillColor)
            let rect = self.bounds(for: box)
            context.fill(rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
            context.restoreGState()
            UIGraphicsPopContext()
        } else {
            let rect = self.bounds(for: box)
            
            UIGraphicsPushContext(context)
            context.saveGState()
            
            context.setBlendMode(.exclusion)
            context.setFillColor(fillColor)
            context.fill(rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
            
            context.setBlendMode(.darken)
            context.setFillColor(gray: 0.7, alpha: 1.0)
            context.fill(rect.offsetBy(dx: -rect.minX, dy: -rect.minY))

            context.restoreGState()
            UIGraphicsPopContext()
        }
        // print("context \(box.rawValue) \(context.height) \(context.width)")
    }
    
    override func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> UIImage {
        let uiImage = super.thumbnail(of: size, for: box)
        
        return uiImage
    }
}
