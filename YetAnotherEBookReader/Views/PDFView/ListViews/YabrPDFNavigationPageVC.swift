//
//  PageViewController.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 14/07/16.
//  Copyright © 2016 FolioReader. All rights reserved.
//

import UIKit

class YabrPDFNavigationPageVC: UIPageViewController {
    var yabrPDFView: YabrPDFView?
    var yabrPDFMetaSource: YabrPDFMetaSource?
    
    var segmentedControl: UISegmentedControl!
    
    var viewList = [UIViewController]()
    var segmentedControlItems = [String]()
    
    let chapterViewController = YabrPDFChapterList()
    let thumbnailViewController = YabrPDFThumbnailList()
    let referenceViewController = YabrPDFReferenceList()

    var index: Int = 0

    // MARK: Init

    init() {
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)

        self.edgesForExtendedLayout = UIRectEdge()
        self.extendedLayoutIncludesOpaqueBars = true
    }

    required init?(coder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewList = [chapterViewController, thumbnailViewController]
        chapterViewController.didMove(toParent: self)
        thumbnailViewController.didMove(toParent: self)
        
        segmentedControlItems = ["Chapter", "Thumbnail"]
        
        if self.yabrPDFMetaSource?.yabrPDFReferenceText(yabrPDFView) != nil {
            viewList.append(referenceViewController)
            referenceViewController.didMove(toParent: self)
            
            segmentedControlItems.append("Reference")
        }
        
        segmentedControl = UISegmentedControl(items: segmentedControlItems)
        segmentedControl.addTarget(self, action: #selector(YabrPDFNavigationPageVC.didSwitchMenu(_:)), for: UIControl.Event.valueChanged)
        segmentedControl.selectedSegmentIndex = index
        
        self.navigationItem.titleView = segmentedControl

        self.delegate = self
        self.dataSource = self

        self.view.backgroundColor = UIColor.white
        if index >= viewList.count {
            index = 0
        }
        self.setViewControllers([viewList[index]], direction: .forward, animated: false, completion: nil)

        // FIXME: This disable scroll because of highlight swipe to delete, if you can fix this would be awesome
        for view in self.view.subviews {
            if view is UIScrollView {
                let scroll = view as! UIScrollView
                scroll.bounces = false
            }
        }

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(dismiss))
        
        if let fillColor = PDFPageWithBackground.fillColor {
            segmentedControl.selectedSegmentTintColor = UIColor(cgColor: fillColor)
        }
        
        if let textColor = chapterViewController.textColor {
            segmentedControl.setTitleTextAttributes([.foregroundColor: textColor], for: .normal)
        }
    }

    // MARK: - Segmented control changes

    @objc func didSwitchMenu(_ sender: UISegmentedControl) {
        let direction: UIPageViewController.NavigationDirection = (index > sender.selectedSegmentIndex ? .reverse : .forward)
        self.index = sender.selectedSegmentIndex
        setViewControllers([viewList[index]], direction: direction, animated: true, completion: nil)
    }

    // MARK: - Status Bar

    override var preferredStatusBarStyle : UIStatusBarStyle {
        yabrPDFMetaSource?.yabrPDFOptionsIsNight(yabrPDFView, .lightContent, .default) ?? .default
    }
    
    // MARK: - NavBar Button
    
    @objc func dismiss(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true)
    }
}

// MARK: UIPageViewControllerDelegate

extension YabrPDFNavigationPageVC: UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {

        if finished && completed {
            let viewController = pageViewController.viewControllers?.last
            segmentedControl.selectedSegmentIndex = viewList.firstIndex(of: viewController!)!
        }
    }
}

// MARK: UIPageViewControllerDataSource

extension YabrPDFNavigationPageVC: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {

        let index = viewList.firstIndex(of: viewController)!
        if index == viewList.count - 1 {
            return nil
        }

        self.index = self.index + 1
        return viewList[self.index]
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {

        let index = viewList.firstIndex(of: viewController)!
        if index == 0 {
            return nil
        }

        self.index = self.index - 1
        return viewList[self.index]
    }
}

