//
//  SwiftUI_Ad_Banner.swift .swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/2.
//

import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

private struct BannerVC: UIViewControllerRepresentable  {

    let adUnitID: String
    
    init(adUnitID: String) {
        self.adUnitID = adUnitID
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        
        #if canImport(GoogleMobileAds)
        let view = BannerView(adSize: AdSizeBanner)

        view.adUnitID = self.adUnitID
        view.rootViewController = viewController
        viewController.view.addSubview(view)
        viewController.view.frame = CGRect(origin: .zero, size: AdSizeBanner.size)
        view.load(Request())
        #endif

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        
    }
}

struct Banner: View{
    @Environment(\.appContainer) var container
    
    var body: some View{
        HStack {
            if let adUnitID = YabrAppInfo.shared.gadBannerShelfUnitID {
                Spacer()
                BannerVC(adUnitID: adUnitID).frame(width: 320, height: 50, alignment: .center)
                Spacer()
            }
        }
    }
}

struct Banner_Previews: PreviewProvider {
    static private var container = AppContainer()

    static var previews: some View {
        Banner()
            .environment(\.appContainer, container)
    }
}
