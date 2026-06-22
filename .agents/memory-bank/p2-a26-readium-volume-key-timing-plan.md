# P2-A26 Readium Volume Key Timing Hack Plan

## Context

A26 was originally recorded as "Readium ViewController timing hack" with two
fixed `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` calls in
`YabrReadiumReaderViewController.swift`. After the current A27 state, the live
code shows both delays are in the Readium volume-key paging path, not in the
initial Readium locator loading path:

- `YabrReadiumReaderViewController.swift:603` resets the system volume to the
  0.5 baseline and unlocks `isHandlingVolumeChange` after 0.1 seconds.
- `YabrReadiumReaderViewController.swift:655` retries `setSystemVolume` every
  0.1 seconds until `MPVolumeView` lazily creates its internal `UISlider`.

The behavior is low severity but user-visible: volume-key paging can skip,
double-trigger, or fail to initialize depending on device speed, audio-session
state, MPVolumeView readiness, and Readium navigation timing.

## Current Code Shape

Primary files:

- `Views/ReadiumView/YabrReadiumReaderViewController.swift`
  - owns `MPVolumeView`, `AVAudioSession`, KVO on `outputVolume`,
    event direction detection, rate limiting, baseline reset, and default page
    navigation.
- `Views/ReadiumView/YabrReadiumEPUBViewController.swift`
  - overrides `handleVolumeKey(up:)` to scroll the active `WKWebView` in EPUB
    scroll mode or fall back to Readium page navigation.
- `Views/ReadiumView/YabrReadiumPDFViewController.swift`
  - inherits the base volume-key behavior.
- `Views/Reader/YabrReaderSettingsView.swift`
  - exposes the `volumeKeyPaging` preference.
- `Views/Reader/YabrEBookReader.swift`
  - loads/saves `ReadiumPreferenceRealm.volumeKeyPaging`.

Important current behavior:

- Programmatic baseline reset is detected by comparing `outputVolume` to
  `lastRequestedVolume`.
- Large volume jumps are interpreted relative to the requested 0.5 baseline to
  infer the user's physical key direction.
- `isHandlingVolumeChange` suppresses rapid repeated KVO events while a volume
  key event is being handled.
- EPUB scroll mode uses `setContentOffset(_:animated:)` rather than Readium
  page navigation.

## Problems To Solve

- Time-based unlock: event handling is unlocked after 0.1 seconds regardless of
  whether navigation, scroll animation, or programmatic volume reset has
  actually settled.
- Time-based slider readiness: `setSystemVolume` polls MPVolumeView internals
  with a fixed delay, which can fail on slow devices or waste retries on fast
  devices.
- Testability gap: direction detection, rate limiting, and baseline-reset logic
  are embedded in a view controller and tied to AVFoundation/MediaPlayer.
- Lifecycle coupling: setup runs from init, `viewWillAppear`, settings changes,
  foreground notifications, and teardown; a future fix must not create duplicate
  observers or leave AVAudioSession active.

## Scope

In scope:

- Remove the two 0.1-second fixed delays from the Readium volume-key paging
  path.
- Extract the event interpretation and lock/unlock state into small testable
  units.
- Keep the existing user-facing behavior for EPUB paged mode, EPUB scroll mode,
  PDF mode, RTL navigation, app background/foreground, and settings toggles.
- Add focused unit tests for pure event handling and lifecycle guard behavior.

Out of scope:

- Redesigning Readium reader preferences.
- Implementing Readium highlight rendering.
- Changing FolioReader or YabrPDF volume-key behavior.
- Replacing MPVolumeView with private APIs or adding new dependencies.
- Changing the persisted `ReadiumPreferenceRealm` schema.

## Recommended Architecture

Use a small coordinator/helper instead of keeping all timing state in
`YabrReadiumReaderViewController`:

- `ReadiumVolumeKeyEventResolver`
  - pure Swift type that receives old/new volume and optional requested
    baseline, then returns `.ignoreProgrammatic`, `.pageUp`, `.pageDown`, or
    `.ignoreBusy`.
- `ReadiumVolumeKeyPagingCoordinator`
  - owns the handling state, requested baseline, and reset lifecycle.
  - exposes methods like `startHandlingUserEvent(...)`,
    `markBaselineResetRequested(_:)`, and `finishBaselineResetIfMatched(...)`.
- `YabrReadiumReaderViewController`
  - remains responsible for UIKit/AVFoundation wiring, MPVolumeView discovery,
    and calling reader navigation.

For slider readiness, prefer layout-driven discovery:

- Add a helper that recursively finds the MPVolumeView `UISlider`.
- Call it after adding MPVolumeView, after `view.layoutIfNeeded()`, and from
  `viewDidLayoutSubviews` while setup is pending.
- Only set the baseline once a slider exists.
- Avoid recursive wall-clock retry. Keep a bounded fallback path only as a
  logged no-op if UIKit never exposes a slider.

For event unlock, prefer event completion:

- Replace `handleVolumeKey(up:)` with an async-compatible boundary, for example
  `performVolumeKeyPage(up:) async`.
- Base implementation awaits Readium navigation.
- EPUB scroll mode can complete after issuing `setContentOffset` and observing
  either `scrollViewDidEndScrollingAnimation` through a small delegate proxy or
  a synchronous non-animated fallback in tests.
- Reset baseline and unlock in a `defer` after the explicit action completes.

## Staged Plan

### A26-S1 Characterize Current Behavior

Goal: document and freeze the existing volume-key behavior before replacing
timing hacks.

Actions:

- Add a short audit note in the implementation PR describing current event
  paths: setup, KVO event, direction inference, page action, reset baseline,
  foreground/background teardown.
- Add pure unit tests for direction inference using representative old/new
  volume pairs:
  - normal volume up/down
  - programmatic reset match
  - large jump relative to baseline
  - busy-state suppression

Validation:

- New tests fail before helper extraction only if expectations are encoded
  incorrectly; otherwise they become the safety net for S2.

### A26-S2 Extract Event Resolver And Coordinator

Goal: separate timing-sensitive state from the view controller without changing
behavior yet.

Actions:

- Add `ReadiumVolumeKeyPagingCoordinator.swift` under `Views/ReadiumView/`.
- Move direction inference and busy/requested-baseline handling into the helper.
- Keep the existing asyncAfter calls temporarily but route state transitions
  through the helper.
- Add tests for coordinator lock/unlock and baseline reset matching.

Validation:

- Unit tests for resolver/coordinator.
- Build the app target to catch Readium target membership issues.

### A26-S3 Replace Slider Polling With Layout-Driven Readiness

Goal: remove the `setSystemVolume` retry loop at line 655.

Actions:

- Extract `findVolumeSlider(in:)`.
- Track a `pendingBaselineVolume` when volume-key paging setup begins.
- Attempt baseline set after MPVolumeView insertion and layout.
- Retry from `viewDidLayoutSubviews` while a pending baseline exists.
- Log and leave paging disabled or pending if the slider never becomes
  discoverable, rather than recursively scheduling wall-clock retries.

Validation:

- Unit-test `findVolumeSlider(in:)` with synthetic view hierarchies.
- Manual smoke check on simulator/device: enabling volume-key paging does not
  show the volume HUD and does not crash if the slider is unavailable.

### A26-S4 Replace Event Unlock Delay With Explicit Completion

Goal: remove the 0.1-second unlock/reset delay at line 603.

Actions:

- Introduce `performVolumeKeyPage(up:) async` on the base reader controller.
- Have base Readium navigation await `goLeft`/`goRight`.
- Have EPUB scroll mode return only after the scroll operation is scheduled or
  after a small testable scroll animation completion adapter is notified.
- Reset baseline immediately after the action boundary completes.
- Unlock `isHandlingVolumeChange` through the coordinator after the baseline
  reset request is recorded or matched.

Validation:

- Coordinator tests proving two rapid user events do not double-trigger while
  one is in flight.
- Manual smoke check for EPUB paged mode, EPUB scroll mode, PDF mode, and RTL.

### A26-S5 Harden Lifecycle And Settings Toggles

Goal: prevent observer/session leaks while preserving foreground/background
behavior.

Actions:

- Make setup idempotent if volume-key paging is already active.
- Make teardown clear pending baseline, handling state, observer, volume view,
  and audio session consistently.
- Verify settings toggles call setup/teardown exactly once per transition.
- Keep app background teardown and foreground setup behavior.

Validation:

- Unit-test coordinator reset behavior.
- Manual smoke check: toggle volume-key paging on/off repeatedly, background and
  foreground the app, then press volume keys.

### A26-S6 Documentation And Final Verification

Goal: close A26 with clear handoff notes.

Actions:

- Update `AGENTS.md`, `activeContext.md`, and refactor progress docs after
  implementation.
- Add a short comment near the volume-key coordinator explaining why fixed
  delays are avoided.
- Re-run `rg "asyncAfter\\(deadline: \\.now\\(\\) \\+ 0\\.1"` to verify the
  targeted Readium hacks are gone.

Validation:

- Run focused tests for the new coordinator.
- Run full `xcodebuild test` if practical.
- Run Mac Catalyst build only if current SPM package resolution allows it;
  otherwise record the known `R2Navigator`/`GCDWebServer` product-resolution
  blocker.

## Risks

- MPVolumeView internals are UIKit-managed and not part of a stable public
  object model; readiness must be defensive.
- Hardware volume keys are hard to automate in XCTest, so pure unit tests must
  cover state logic while final behavior still needs device smoke testing.
- AVAudioSession ownership can affect other audio apps; teardown must keep
  `.notifyOthersOnDeactivation`.
- EPUB scroll mode differs from paged Readium navigation and should not be
  forced through the same completion path without verifying scroll behavior.

## Recommended Next Action

Start with A26-S1 and A26-S2 together: extract the pure event resolver and
coordinator with tests while preserving behavior. Once the state machine is
covered, remove the two fixed delays in separate, easy-to-review commits.
