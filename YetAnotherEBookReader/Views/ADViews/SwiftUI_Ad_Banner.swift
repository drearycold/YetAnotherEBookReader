//
//  SwiftUI_Ad_Banner.swift .swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/2.
//

import SwiftUI
import UIKit
import GoogleMobileAds

final private class BannerVC: UIViewControllerRepresentable  {

    let adUnitID: String
    
    init(adUnitID: String) {
        self.adUnitID = adUnitID
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let view = GADBannerView(adSize: GADAdSizeBanner)

        let viewController = UIViewController()
        view.adUnitID = self.adUnitID
        view.rootViewController = viewController
        viewController.view.addSubview(view)
        viewController.view.frame = CGRect(origin: .zero, size: GADAdSizeBanner.size)
        view.load(GADRequest())

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        
    }
}

struct Banner: View{
    @EnvironmentObject var modelData: ModelData
    
    var body: some View{
        #if DEBUG
        HStack{
            Spacer()
            BannerVC(adUnitID: "ca-app-pub-3940256099942544/2934735716").frame(width: 320, height: 50, alignment: .center)
            Spacer()
        }
        #else
        HStack{
            Spacer()
            BannerVC(adUnitID: modelData.resourceFileDictionary?.value(forKey: "GADBannerShelfUnitID") as? String ?? "ca-app-pub-3940256099942544/2934735716").frame(width: 320, height: 50, alignment: .center)
            Spacer()
        }
        #endif
    }
}

struct Banner_Previews: PreviewProvider {
    static private var modelData = ModelData()

    static var previews: some View {
        Banner()
            .environmentObject(modelData)
    }
}
