//
//  YabrPDFAnnotationView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/19.
//

import Foundation
import UIKit

class YabrPDFAnnotationView: UIStackView {
    let dictViewerButton = UIButton()
    let highlightButton = UIButton()
    let underlineButton = UIButton()
    
    init() {
        let dictViewerImage = UIImage(systemName: "character.book.closed")?
            .resizableImage(withCapInsets: .zero, resizingMode: .stretch)
        dictViewerButton.setImage(dictViewerImage, for: .normal)
        
        let highlightImage = UIImage(systemName: "paintbrush")?
            .resizableImage(withCapInsets: .zero, resizingMode: .stretch)
        highlightButton.setImage(highlightImage, for: .normal)
        
        let underlineImage = UIImage(systemName: "highlighter")?
            .resizableImage(withCapInsets: .zero, resizingMode: .stretch)
        underlineButton.setImage(underlineImage, for: .normal)
        
        super.init(frame: .zero)
        
        self.axis = .vertical
        self.addArrangedSubview(dictViewerButton)
        self.addArrangedSubview(underlineButton)
        self.addArrangedSubview(highlightButton)
        
        self.layer.cornerRadius = 8
        self.layer.borderWidth = 1
        self.layer.borderColor = UIColor.gray.withAlphaComponent(0.6).cgColor
        self.distribution = .fillProportionally
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
