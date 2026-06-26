# Refactoring Analysis Context

## Date: 2026-06-06

## Summary
A comprehensive architectural analysis was performed on the entire YetAnotherEBookReader codebase (28,702 Swift lines, 88 files).

## Key Findings

### Top 5 Critical Issues (P0)
1. **ModelData God Object** (2180 lines, 18 @Published properties) — needs splitting into 5-7 service classes
2. **Zero test coverage** — only 1 placeholder test exists
3. **RealmSwift leaked into 36 files** including 20+ view files — needs Repository pattern

### Architecture Stats
- Schema version: 137 (very high migration debt)
- `CalibreLibrarySearchManager` is the class in `CalibreBrowser.swift` (2137 lines)
- FolioReaderKit used via 7 files, Readium via 10 files (ReadiumShared + ReadiumNavigator)
- Reading position save/restore is triplicated across 3 reader engines
- V2 migration started but only covers search (156 lines vs V1's 2137 lines)

### Refactoring Plan
Full plan at: `~/.gemini/antigravity/brain/6899dc7b-d068-4b64-98ae-678c877182ce/REFACTOR_PLAN.md`

### Key Class Names (for future reference)
- `ModelData` — central state (Models/ModelData.swift)
- `CalibreLibrarySearchManager` — search/browse engine (Models/CalibreBrowser/CalibreBrowser.swift)
- `CalibreServerService` — network API (Network/CalibreServerService.swift)
- `BookDownloadManager` — download management (Network/BookDownloadManager.swift)
- `YabrPDFViewController` — PDF reader (Views/PDFView/YabrPDFViewController.swift, 1716 lines)
- `YabrReadiumReaderViewController` — Readium reader (Views/ReadiumView/, 747 lines)
