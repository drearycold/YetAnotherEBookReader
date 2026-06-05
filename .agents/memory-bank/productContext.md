# Product Context: YetAnotherEBookReader (D.S.Reader)

## Purpose
YetAnotherEBookReader (publicly known as D.S.Reader) is a versatile, high-performance, and modern e-book reader designed for iOS (15.0+) and macOS (12.0+ via Catalyst). Its primary goal is to provide native rendering for EPUB, PDF, and CBZ formats while maintaining deep and seamless integration with Calibre content servers for cloud synchronization of libraries and reading progress.

## Core Features
- **Multi-Format Native Rendering:** Supports EPUB, PDF, and CBZ using the Readium 3.8 R2 SDK and FolioReaderKit (for legacy EPUBs).
- **Calibre Sync:** Full integration with Calibre content servers to sync metadata, shelves, and cross-device reading positions.
- **Modernized & Accessible UI:** Unified SwiftUI-based settings, dynamic margins, theme support (Light, Dark, Sepia), RTL (Right-to-Left) progression support, volume key paging, and VoiceOver optimizations.

## Architecture & Tech Stack
- **UI Frameworks:** SwiftUI (iOS 15+) and UIKit.
- **State Management:** Centralized via `@StateObject` `ModelData` (`Models/ModelData.swift`), which manages application state, database initialization, and server connectivity. All app-wide state is accessed using `@EnvironmentObject var modelData: ModelData`.
- **Persistence:** RealmSwift is strictly used for storing metadata, highlights, shelves, and reading progress.
- **Networking & Assets:** `CalibreServerService` handles API interactions with Calibre servers. GCDWebServer serves local book assets to web-based reader views, while Kingfisher handles efficient image caching. 
- **Concurrency:** Asynchronous operations extensively use Combine and `DispatchQueue` for non-blocking I/O and server requests.
- **Dependency Management:** Pure Swift Package Manager (SPM) only; the project deliberately avoids CocoaPods or Xcode Workspaces.

