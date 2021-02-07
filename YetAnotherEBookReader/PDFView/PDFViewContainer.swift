//
//  PDFViewContailer.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import Foundation

@available(macCatalyst 14.0, *)
class PDFViewContainer : UIViewController {
    
    var bookDetailView: BookDetailView?
    
    override func loadView() {
        super.loadView()
        
    }
    
    func open(pdfURL: URL, bookDetailView: BookDetailView) {
        self.bookDetailView = bookDetailView
        
        let pdfViewController = PDFViewController()
        
        let nav = UINavigationController(rootViewController: pdfViewController)
        nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        nav.navigationBar.isTranslucent = false
        nav.setToolbarHidden(false, animated: true)
        
        pdfViewController.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        pdfViewController.open(pdfURL: pdfURL, bookDetailView: bookDetailView)
        
        let stackView = UIStackView(frame: nav.toolbar.frame)
        stackView.distribution = .fill
        stackView.alignment = .top
        stackView.axis = .horizontal
        stackView.spacing = 8.0
        
        stackView.addArrangedSubview(pdfViewController.pageSlider)
        stackView.addArrangedSubview(pdfViewController.pageIndicator)
        
        let toolbarView = UIBarButtonItem(customView: stackView)
        pdfViewController.setToolbarItems([toolbarView], animated: false)
        
        self.present(nav, animated: true, completion: nil)
        
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}
