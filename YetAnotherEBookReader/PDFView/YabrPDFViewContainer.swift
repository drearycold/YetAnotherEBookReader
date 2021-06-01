//
//  PDFViewContailer.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import Foundation

@available(macCatalyst 14.0, *)
class YabrPDFViewContainer : UIViewController {
    
    var bookDetailView: BookDetailView?
    
    override func loadView() {
        super.loadView()
        
    }
    
    func open(pdfURL: URL) {
        let pdfViewController = YabrPDFViewController()
        
        let nav = UINavigationController(rootViewController: pdfViewController)
        nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        nav.navigationBar.isTranslucent = false
        nav.setToolbarHidden(false, animated: true)
        
        pdfViewController.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        pdfViewController.open(pdfURL: pdfURL)
        
        let stackView = UIStackView(frame: nav.toolbar.frame)
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.axis = .horizontal
        stackView.spacing = 16.0
        
        stackView.addArrangedSubview(pdfViewController.pagePrevButton)
        stackView.addArrangedSubview(pdfViewController.pageSlider)
        stackView.addArrangedSubview(pdfViewController.pageIndicator)
        stackView.addArrangedSubview(pdfViewController.pageNextButton)
        
        let toolbarView = UIBarButtonItem(customView: stackView)
        pdfViewController.setToolbarItems([toolbarView], animated: false)
//        pdfViewController.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 256, right: 0)
        
        
        if let navCtrl = self.navigationController {
            navCtrl.present(nav, animated: true, completion: nil)
        } else {
            self.present(nav, animated: true, completion: nil)
        }
        
        
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}
