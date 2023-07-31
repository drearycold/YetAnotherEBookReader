//
//  DictWebView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/31.
//

import Foundation
import WebKit

internal class DictWebView: WKWebView {
    
    let activityView = UIActivityIndicatorView()
    let labelView = UILabel()
    
    init() {
        super.init(frame: .zero, configuration: .init())
        
        activityView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(activityView)
        NSLayoutConstraint.activate([
            activityView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.6),
            activityView.heightAnchor.constraint(equalToConstant: 32),
            activityView.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        activityView.style = .medium
        activityView.hidesWhenStopped = true
        activityView.startAnimating()
        
        labelView.textAlignment = .center
        labelView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.6),
            labelView.heightAnchor.constraint(equalToConstant: 96),
            labelView.centerXAnchor.constraint(equalTo: centerXAnchor),
            labelView.bottomAnchor.constraint(equalTo: activityView.topAnchor)
        ])

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
