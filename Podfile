# Uncomment the next line to define a global platform for your project
platform :ios, '14.0'

target 'YetAnotherEBookReader' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for YetAnotherEBookReader
  pod 'Google-Mobile-Ads-SDK'
  pod 'Kingfisher/SwiftUI', '~> 5.0'
  # pod 'Realm', '~> 5.0'
  # pod 'RealmSwift', '~> 5.0'
  pod 'ShelfView', :path => '../ShelfView-iOS'  
  pod 'FolioReaderKit', path: '../FolioReaderKit'

pod 'R2Shared', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/2.4.0/Support/CocoaPods/ReadiumShared.podspec'
pod 'R2Streamer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/2.4.0/Support/CocoaPods/ReadiumStreamer.podspec'
pod 'R2Navigator', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/2.4.0/Support/CocoaPods/ReadiumNavigator.podspec'
pod 'ReadiumOPDS', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/2.4.0/Support/CocoaPods/ReadiumOPDS.podspec'
pod 'ReadiumLCP', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/2.4.0/Support/CocoaPods/ReadiumLCP.podspec'

pod 'GCDWebServer', podspec: 'https://raw.githubusercontent.com/readium/GCDWebServer/3.7.3/GCDWebServer.podspec'

  pod 'MBProgressHUD', '~> 1.2.0'

  target 'YetAnotherEBookReaderTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'YetAnotherEBookReaderUITests' do
    # Pods for testing
  end

end

target 'YetAnotherEBookReader-Catalyst' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for YetAnotherEBookReader
  pod 'Kingfisher/SwiftUI', '~> 5.0'
  pod 'ShelfView', :path => '../ShelfView-iOS'  
  pod 'FolioReaderKit', path: '../FolioReaderKit'
  # pod 'Realm', '~> 5.0'
  # pod 'RealmSwift', '~> 5.0'

end

post_install do |installer|
   installer.pods_project.targets.each do |target|
       #flutter_additional_ios_build_settings(target)
       target.build_configurations.each do |config|
          if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 12.0
            config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
          end
       end
   end
end
