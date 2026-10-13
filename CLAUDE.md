# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

AGENTS.md is the project's agent guide, shared with other agents. It covers build and test
commands, CI, Swift packages, the simulator set, the architecture map, and the coding and Realm
threading rules. It is imported below. Put project rules there, not here; this file only adds
what Claude Code needs on top.

@AGENTS.md

## Before and after a task

Read `.agents/memory-bank/activeContext.md` first: branch notes, known failures, and the
verification history. Update it when a task changes test status, risks, or handoff context.

## Running tests

Unit tests run inside the app on a simulator: `YetAnotherEBookReader.app` is the test host.
Shut simulators down first (`xcrun simctl shutdown all`).

- One class or one test: add `-only-testing:` to the AGENTS.md test command.

  ```bash
  xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/MainViewModelTests/testRecentShelfTapPublishesReaderPresentation
  ```

- To rerun without rebuilding, as CI does: run `build-for-testing` once, then
  `test-without-building` with the same flags.
- The full unit suite takes about 3–4 minutes on a desktop Mac; `YabrPDFMarginCropTests` is most
  of it.
- `PDFMarginDetectionBenchmarkTests` is skipped unless `TEST_RUNNER_YABR_BENCHMARK=1` is set.
  For optimized numbers, also pass `SWIFT_OPTIMIZATION_LEVEL=-O` and use separate derived data.
- UI journeys: `-only-testing:YetAnotherEBookReaderUITests`. They launch the app with
  `--ui-testing-mock-library`, an offline mock library (`UITestingConfiguration`). Performance
  experiments use the `YetAnotherEBookReader-UI-Performance` scheme and
  `UITestPerformance.xctestplan`.

## Tests that pass on CI

CI runs on a fresh simulator on a 3-core runner. The suite takes about 1.5x as long there as on a
desktop Mac, and PDF rendering 3–5x.

- **Don't rely on files left over from earlier runs.** `MockAppContainerFactory.makeContainer`
  builds `AppContainer(mock:)`. That lists the mock book's EPUB as cached, but writes the file
  only in UI-testing mode. Tests that open the mock book call
  `TestFixtures.cacheMockBookEPUB(in:)`.
- **Reproduce a fresh-simulator failure locally** by moving a directory in the test host's
  `Documents` aside, then putting it back afterwards. Find the container with
  `xcrun simctl get_app_container <udid> io.github.drearycold.DSReader data`.
- **Wait on a deadline.** Wait for an asynchronous result with a loop that ends when its
  condition holds, bounded generously (10 s, as `YabrPDFMarginCropTests.waitTimeout`). A fixed
  number of short sleeps runs out on the runner.
- **Leave the terms accepted.** The test host detects `XCTestConfigurationFilePath`: it skips the
  tracking and ad-consent prompts and accepts the terms
  (`UITestingConfiguration.skipsConsentPrompts`). A test that changes the terms default must
  restore it (see `MainViewModelTests.tearDownWithError`).

## Adding files

The project uses explicit file references (no synchronized folders), so a new file must be
registered in `project.pbxproj` by hand:

- an app source belongs to both the `YetAnotherEBookReader` and `YetAnotherEBookReader-Catalyst`
  targets;
- a test belongs to `YetAnotherEBookReaderTests` only.

A missing registration only shows up when that target builds, so build both the iOS app and
Catalyst.
