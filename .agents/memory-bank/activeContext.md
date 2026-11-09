# Active Context

## Current Focus

`codex/yabr-pdf-optimization`: fix YabrPDF single-page margin-crop viewport
placement (content right of center, top offset / drift after page turns).

## App Marketing Version 0.3 (2026-11-08)

`codex/bump-app-version-0-3` starts at main `6b798872` after BD4 #139.
The iOS and Catalyst Debug/Release app configurations now use marketing
version **0.3**. Both Info.plist files derive CFBundleShortVersionString from
MARKETING_VERSION. Xcode continues to manage distributed build numbers.
Validation passed: project and plist syntax, all four app configuration values,
plist version bindings, and `git diff --check`. No build or test run for this
configuration-only change.

## Book Detail Modernization BD4 (2026-11-08)

`codex/book-detail-bd4` starts at `ea391b50` on main. BD3 PR #138 merged
with Detect changes, iOS unit tests, Calibre contract tests and Mac Catalyst
all passing for head `7b820e7f`.

Book Detail owns a dedicated inline HTML renderer. Its input is the description
markup and the base URL, so progress and refresh state reuse the same document.
A document token rejects late layout messages. WebKit measures natural body
height after width, font or resource changes. The native viewport's height
does not trigger another measurement. Long descriptions use a Dynamic Type
scaled fold and the detail page's existing scrolling. Relative resources use
the book's base URL, local anchors scroll the detail page, and external links
use the system URL action. Description content JavaScript is disabled.
Privacy, Terms and release notes still use the shared WebView.

Reading History and Activity Logs now start and cancel their subscriptions at
page visibility on the main actor. Book Detail owns scoped, stable route
models. History keeps the same list model while refreshing that book, and its
position detail keeps the chosen value through the pop animation. Continue
Reading passes the workspace at the point of action and checks the file again.
The Activity sheet owns a separate dismissal subscription, so opening a reader
can close it even after Book Detail has stopped observing. Settings retains
global statistics and global or library-scoped Activity Logs.

The first iPadOS 18.5 Release run caught a launch failure. The Swift WebKit
overlay's `callAsyncJavaScript` added a required `libswiftWebKit` dependency
missing from that simulator runtime. The final binary uses the original WebKit
JavaScript evaluation method and observes the document's style attribute in
the isolated measurement script. The before and after `otool` outputs and the
launch crash are in `/tmp/YabrBD4`. The final Release passed real Safari Split
View on iPadOS 18.5, including opening a description from its internal link
and scrolling to the target. The final Release also passed iPhone 7 / iOS 15.5
with maximum accessibility text and dark appearance. The first iPhone 7 run
needed a longer test-driver scroll budget to reach Activity Logs at that size.

Final verification passed **196 focused unit tests and two UI journeys** on
iPhone 17 / iOS 26.5. On iPhone 7 / iOS 15.5, **121 focused units** and the
Recent/history journey passed after relinking. The Browse journey passed when
rerun at standard text size. It had reached a fixture tap failure when it
inherited maximum text size. The real WKWebView test changes width and text size
without changing the document token, then changes only the base URL and only
the HTML, verifying each new document and relative link resolution. Separate
tests cover the originating workspace for both continue-reading actions,
observation cancellation and Activity dismissal on reader open.

Native Release iPhone 17, iPadOS 26.5 portrait/landscape, BD3 preview/format
operations, P3 download/read/retry/cancel, and the local EPUB flow passed before
the WebKit relink. The final iOS Release, iOS test build, Catalyst build, Swift
parse, project check, proxy syntax and diff checks passed. See
`/tmp/YabrBD4/verification.json` for results and screenshot paths. Simulator
coverage includes relative SVG rendering and an in-description anchor in an
actual split window. Catalyst window interaction, hardware, VoiceOver, and the
system browser handoff for an external link were outside this verification.

### BD4 review follow-up (2026-11-08)

A native HTML `<details>` disclosure changed the description's body height
without a report, leaving the expanded text clipped. The measuring script now
catches `toggle` in the capture phase and reports the natural height without
reloading the document or measuring on viewport height changes.

The real WebKit test reproduced the missing report before the fix. It now
passes on iPhone 17 and iPhone 7 / iOS 15.5, including height growth, collapse,
and an unchanged document token. All 18 focused iPhone 17 tests passed. The
macOS WebKit probe, iOS Release and Catalyst builds, and static checks passed.
The Release binary still has no `libswiftWebKit` dependency. Evidence is in
`/tmp/YabrBD4Disclosure`, with the red run in `/tmp/YabrBD4Review`. The earlier
Release UI matrix above predates this change.

## BD3 review follow-up (2026-11-08)

Browse batch confirmation starts the selected remote formats directly when the
server is reachable. An explicit batch can replace a finished attempt after
cache removal, failure, or cancellation. Offline selection remains queued for
the shelf when the server reconnects. Only an explicit batch retires the old
terminal results for those queued formats. Existing files and active downloads
are reused, including transfers already active at another address.

Book Detail's format row and toolbar display an active attempt ahead of older
records for the same full book ID and format. When the format is idle, they
display the most recently started attempt. Regressions cover all three terminal
results, the offline retry path, and the status and controls across an address
change.

Verification: 177 focused units and the Browse batch selection UI journey passed
on iPhone 17. The two affected test classes passed 100 units on iPhone 7 /
iOS 15.5. The Mac Catalyst build, Swift parsing, and diff checks passed. Logs
and results are in `/tmp/YabrBD3Followup`. The full suite and native Release
journeys below describe the initial BD3 implementation.

## Book Detail Modernization BD3 (2026-11-07, branch)

`codex/book-detail-bd3` starts at main `ca23e853`, with BD1 #136 and BD2 #137
merged; GitHub and `ls-remote` verified the base, and the initial worktree was
clean. The branch contains the BD3 implementation and verification notes.

Files/Formats and the observing toolbar share `BookFormatState` snapshots and
`BookFormatActions`, including format-specific labels, pausing/resuming,
cancellation, failure/retry, actual-file checks, unsupported formats and preview.
Clearing a downloaded format confirms its local-file/Recent effect and keeps
history/annotations; imported local originals offer neither download nor cache
clearing. Commands reconcile the download snapshot immediately, and existing P3
full-book-ID/download-UUID/originating-workspace/open-once intent rules remain.

Each preview owns immutable book and ReaderInfo values and its own identity.
BookPreviewViewModel owns loading/contents/empty/generating/failure/retry and
cancels requests and invalidates their generation on retry or close. Late
answers cannot update a closed preview, a retry, or a different preview. Manifest requests use the existing service with a short
10-second session. Nested titles are retained and malformed/aborted manifests
are recoverable; local and offline contents use the existing Readium publication
parser (EPUB/PDF/CBZ), without a reader/session. The sheet has explicit Close and
a stable tab container; readers mount only after selecting Preview.

Preview no longer prepares/restores the session manager's legacy ReaderInfo.
The actual reader bridge/navigation, Folio position/bookmark/preference providers,
PDF metadata source and Readium preference path suppress preview writes and
session close handling. Folio keeps preview positions in memory; formal
positions, annotations and preferences remain unchanged. The old comment about
restoring a prepared preview session was not a reliable boundary.

Download file callbacks now stage bytes privately, then validate HTTP success,
current download UUID/task and cancellation before replacing the final file.
Failed/cancelled/stale delivery cannot overwrite an older cache or recreate a
cleared file. Completion and start use the latest repository book, preserving
other formats' cache/selection flags and metadata refreshed during the download.
Shelf rebuilds use requestAutomaticDownload, which never restarts known
failed/cancelled/paused attempts in this session; explicit retries still create a
new download. Native P3 reproduced the otherwise automatic second GET after 503.
Deterministic red cases pin the file and snapshot failures before their fixes.

Final validation: **1032 units + five regular UI journeys** pass (22 skips,
two existing expected PDFKit failures, zero unexpected failures). iOS 15.5 passes
**274 focused units + two detail/history UI journeys**. Five isolated
**Release** native journeys pass: complete BD3 on iPhone 17/iOS 26.5 and iPhone
7/iOS 15.5, iPad mini/iPadOS 26.5 portrait/landscape, the full P3 download/read
journey on iPhone 17, and normal-startup local CC0 EPUB preview/read/history.
These cover actual preview entry, original-chapter resume, empty/generating/bad
manifest and retry, local/offline contents, close during response, clearing and
real pause/resume. Final iOS Release/Catalyst builds, changed-Swift parse, Python
compile and diff checks pass. Native copies match the final Release executable
hash. The initial native pass caught a disappearing conditional empty tab; a
stable ZStack fixes it. SwiftUI's Menu exposes an enclosing Other and Button
with the same ID, so the UI driver matches the actual Button label. The reusable
`.github/scripts/calibre-download-proxy.py` exposes `/bd3-control`
for `YABR_PREVIEW_CONTROL_URL`; `YABR_PREVIEW_IPAD=1` selects EPUB using Files
in the opt-in driver while keeping the tablet's normal PDF preference. Evidence:
`/tmp/YabrBookDetailBD3/verification.json`; Chinese report and screenshots:
`/Users/peterlee/.codex/visualizations/2026/11/07/01a1b3bf-a0e8-7cf2-837d-e4857d7aec36/book-detail-bd3/report.html`.

Boundaries: no physical device, HTTPS/Digest, huge-file/disk-pressure stress,
real DSReader Helper or Catalyst interaction. Native readers use EPUB/Folio;
PDF/CBZ file parsing, engine position isolation and old-system PDF fallback have
unit coverage, not native PDF/CBZ annotation/preference journeys. iPad checks are
single-window portrait/landscape, not Split View. The GET proxy doesn't forward
position/annotation POSTs, so real remote writes remain unverified. The original
/tmp package cache was incomplete; builds use fresh `/tmp/YabrBD3Packages` and
separate derived data, with locked versions. No schema, package pin, project
membership or app version/build change. BD4 still owns description WebView
loading/expansion and history/auxiliary internal cleanup.

## BD2 review follow-up: publication date calendar (2026-11-06)

Independent review found that comparing Calendar.current's year with Calibre's
Gregorian sentinel year 101 hides valid dates under Japanese/ROC calendars and
shows missing dates under Buddhist calendars. BookMetadataSection now uses a
fixed Gregorian calendar only for validity; pubDateByLocale still formats the
visible value with the user's locale/calendar.

The pre-fix Japanese test host reproduces hidden 2024/2000 dates. Final pure
value tests avoid AppContainer/Realm state and assert each process's actual
preferred calendar. All **66 focused tests** pass: the full Book Detail class
plus date tests under Gregorian, then date tests under Japanese, ROC and
Buddhist; Japanese also passes on iPhone 7/iOS 15.5. Catalyst build, changed-Swift
parse and diff checks pass. The full/native/Release BD2 records below precede
this follow-up and were not rerun. Evidence:
`/tmp/YabrBD2CalendarReview/verification.json`.

## Book Detail Modernization BD2 (2026-11-06, branch)

`codex/book-detail-bd2` starts at main `4493c21f`, verified through GitHub's API
with BD1 #136 merged. The worktree was clean; the old planning worktree was not
used. BD2 and its calendar-review fix are recorded on this branch for review.

Book Detail now orders overview, reading progress, description, formats,
metadata, optional Count Pages and sync/advanced information. The overview uses
actual container width (two columns from 600pt, vertical below it); accessibility
sizes use vertical layout. Content is capped at 960pt, without repeated 300pt
columns. Long titles/authors wrap, the title appears once, absent publication
fields are omitted, and Goodreads/Count Pages retain configuration gating.
At accessibility sizes the main button uses text without the redundant icon,
leaving enough width for Download. Normal sizes retain the icon.

Body components store displayed fields and action callbacks, not the whole
BookDetailViewModel. The page owns navigation, preview/activity sheets and
alerts. Unused lastUpdated/isCompat/alertItem/viewMode parameters and Mode
call sites are removed. CalibreBook equality is identity-only: a real native
refresh initially changed the title/date while keeping old publisher/tags.
Projection into actual display strings fixes that diffing issue; the old Release
copy fails the new native regression at updated publisher, and final Release
passes on iPhone 17 and iPhone 7/iOS 15.5. Count Pages and description also use
actual display values rather than an identity-only book member.

Final verification: **1001 unit tests + five regular UI journeys** pass (22
unit skips, two existing expected PDFKit failures, no unexpected failures).
The iOS 15 focused run passes **158 units + two detail/history UI journeys**.
Native Release verification covers metadata refresh on both systems, P3 download
and read/cached resume/download-only/retry/cancel/leave, iPhone 7 maximum
accessibility text, iPad portrait/landscape and maximum text, an actual Safari
split window on iPadOS 18.5, and a real coverless local EPUB through Read and History return.
The pre-label-refinement P3/BD1 journeys on both systems also pass. Final iOS
Release and Catalyst builds, Swift parse and diff checks pass. Native Release
copy hashes match the built executable; complete phase-specific evidence:
`/tmp/YabrBookDetailBD2/verification.json`. Chinese report and key screenshots:
`/Users/peterlee/.codex/visualizations/2026/11/06/01a1b067-0d4c-7530-8d01-bbea42f9a4da/book-detail-bd2/report.html`.

Boundaries: description retains its existing 400pt internally scrolling WebView;
loading de-duplication/expansion is BD4. Format-operation and preview-request
ownership remains BD3. The iOS 15 toolbar compatibility host intentionally
still observes BookDetailViewModel. Catalyst interaction uses Debug; simulator
native checks use Release and ordinary controls, with the existing consent gate
only. Local validation seeds a CC0 EPUB in the isolated Local Library folder,
then uses normal startup discovery/persistence and native controls. The iPadOS 26 split attempt did not narrow the window and the simulator
screen API then timed out; it is not counted as passed. No physical
device, HTTPS/Digest, large-file stress or real DSReader Helper interaction.
PDF/CBZ, pause/resume and originating-workspace/open-once retain unit coverage.
No schema, dependency pin, project membership or version/build change. Test-only
scrolling attempts (lazy CollectionView/Table rows, overshoot and scroll-bar
hit areas) are retained; the final helper checks frames and uses slow drags in
the left card padding.

## Book Detail Modernization BD1 (2026-11-06, branch)

`codex/book-detail-bd1` starts from main `ed117bc2df708e8433ce77c1a2c0045346d5d360`,
including first-book P1–4. The connected GitHub API reverified main after shell
DNS failed. The pre-existing uncommitted Folio layered-image analysis is
preserved separately from this commit. BD1 and its review fix are recorded on this branch.

Book Detail receives its container explicitly and owns loading/content/local
unavailable plus per-request refresh states. Full book identity, refresh UUIDs
and observer generations reject late/cancelled answers. Leaving cancels refresh
and observations; History return reattaches local data without a network fetch.
`CalibreBookManager.getBooksMetadata` returns per-book results while retaining
legacy persistence/broadcasts/callers. Server null preserves readable caches;
HTTP failure messages retain status without rendering response bodies.

Reading availability, progress/history and helper configuration are event-driven
snapshots. Rendering does no repository/file queries or ReaderInfo preparation.
Read clicks still confirm files and reuse ReadingSessionManager's format/device
position policy. Repository-owned, main-actor position streams publish values,
not Realm objects. The list model now honors its supplied position snapshot.
P3's full ID/download UUID/originating workspace, one successful ready-file open,
retry, pause/resume and cancel/leave/history/preview intent revocation are kept.
Unavailable/failed refreshes label cached formats Downloaded. The iOS 15 native
journey reproduced frozen download/refresh toolbar labels even after content
updated; one hosted observing View inside toolbar items fixes both, retains the
history button, and always uses the model's current book.

Pre-review verification: **999 unit tests** (22 skips, two existing expected PDFKit
failures) and **five regular UI journeys** pass on iPhone 17 / iOS 26.5.
Related **206-unit** runs pass on both systems; after the toolbar fix, **107**
iOS 15 units pass, then the final **54 BookDetail units + two Recent/Browse UI
journeys** pass. All **four real-Calibre native journeys** (BD1 + P3 on iPhone 17
and iPhone 7 / iOS 15.5), final Catalyst build, changed-Swift parse and diff checks
pass. Native executable/debug-dylib hashes match the final product. The old
availability test now expects Readium PDF on iOS 15, honoring the existing iOS 16
YabrPDF boundary. Red missing/deleted-book and stale-toolbar proofs are retained.
Evidence, summaries and source/binary hashes: `/tmp/YabrBookDetailBD1/verification.json`.

Boundary: no physical device, iPad, Catalyst interaction, HTTPS/Digest or large-file
stress run. Native reading uses EPUB/Folio and local resume; PDF/CBZ, pause/resume
and multi-workspace/open-once invariants have unit coverage. The existing read-only
proxy does not forward sync POSTs (501), so native remote position/annotation
writes are unverified. BD2 layout, BD3 format/preview request ownership and BD4
WebView/auxiliary cleanup remain separate; preview manifest task ownership is
unchanged. No package pins, Realm schema, app version or build number changed.

### BD1 review follow-up: cancellation after persistence (2026-11-06)

Confirmed the review finding with two deterministic real-Realm regressions:
cancellation before the queued write commits and after commit both left stale
shelf values; clearing cache then overwrote the new title. Once persistence is
queued, the manager now completes snapshot/status reconciliation and notifications
before returning cancelled. Cancellation prevents new annotation work, uploads
and retries, including uploads after an already-running annotation sync finishes.
Book notifications prefer the committed snapshot because the main Realm may not
yet have advanced to the background commit.

Both red cases reproduce on the previous implementation. Final **104 focused
unit tests** pass (BookDetailViewModel, CalibreBookManager, BookMetadataSyncWorker,
BookDownloadManager), including notification content and preserving metadata
through cache clearing. Swift parse and diff checks pass. This follow-up did not
repeat the full suite, native UI journeys or Catalyst; the results above describe
the pre-review state. Evidence: `/tmp/YabrBD1CancelReview/verification.json`.

## First Book Connection Recovery P4 (2026-11-06, branch)

`codex/first-book-connection-recovery` starts at latest main `7d2c442c`,
including P1 #132, P2 #133 and P3 #134; the initial worktree was clean.
GitHub's connected API verified main after shell DNS failed; its exact signed
merge commit was reconstructed and hash-verified, with the same tree as the
local P3 tip. No existing work was replaced.

Connection setup now presents bounded, actionable messages and HTTP status,
with **Edit Connection** and **Retry** on the error's first screen. Raw server
bodies never enter this UI; no technical-details panel is offered. Editing
preserves all inputs. Probe staging propagates structured errors and per-probe
HTTP context (including rejected authentication challenges), and probes use
current addresses/credentials. Shared `CalibreAPIError` cases/descriptions stay
unchanged. Same-configuration background probes retain last-known reachability
until their answer; a failed probe clears its library result. Failed/cancelled
probes still cannot confirm, save or browse.

Final validation: **982 unit tests** (22 skips, two existing expected PDFKit
failures), **five existing UI journeys**, **119 focused iOS 15.5 tests**, iOS
Release and Catalyst builds pass. Complete **Release** native journeys pass on
iPhone 17/iOS 26.5 and small-screen iPhone 7/iOS 15.5: ~100 KB HTML 503,
HTTP 401/403, connection refusal, missing/wrong Basic credentials, correction,
retry, no save after failure/relaunch, modification with retained input,
update persistence and actual Calibre book lists after recovery. Edit/Retry
are hittable and wholly on screen without scrolling each error page. The
isolated app's executable hash matches the Release product. Tests use ordinary
native controls, normal persistence/network and the existing consent skip.

Boundary: authentication is a controlled real HTTP Basic challenge; successful
read APIs forward to actual local anonymous Calibre. No physical device, iPad,
live HTTPS/certificate or Digest run. No schema, pins or versions changed.
Fixture: `.github/scripts/calibre-connection-proxy.py`. Evidence and retained
harness attempts: `/tmp/YabrConnectionRecoveryP4/verification.json`; Chinese
report: `/Users/peterlee/.codex/visualizations/2026/11/05/01a1ac66-6863-7f12-8f73-9410a22cf077/connection-recovery-p4/report.html`.

## First Book Download and Read P3 (2026-11-05, branch)

Independent read-only review against `5b0aff44`, including staged, unstaged
and untracked changes, found no actionable issues. Prepared for a PR to main.

`codex/first-book-download-read` starts at fetched `main` `5b0aff44`, with P1
#132 and P2 #133 merged; initial worktree clean. Book Detail now has textual,
accessibly named **Download and Read** / **Read**, plus **Download Only**.
A pending read binds the full book ID, download UUID and originating workspace.
Only successful, ready files open once; cancellation, leaving detail, history,
preview or another reader opening clears the intent. Existing format selection
and reading-session position policy are reused. Download terminal outcomes also
prevent late pause data from reactivating a cancelled attempt.

Final validation: **976 unit tests** (22 skips, two existing expected PDFKit
failures), **five existing UI journeys**, **64 focused iOS 15.5 tests**, iOS and
Catalyst builds, and complete isolated real-Calibre journeys on iPhone 17/iOS
26.5 and iPhone 7/iOS 15.5 all pass. Success, cached resume, download-only, 503
retry, cancellation and leaving detail are covered. Native EPUB/Folio checks
use ordinary controls and normal disk/network, with the existing consent skip
flag only; PDF/CBZ and old-system PDF fallback are covered by units.

Observed boundary: iOS 15's auxiliary toolbar download/clear label can lag cache
changes; the native journey uses the existing format-row clear button. The
primary reading text/name is correct. No physical device, iPad, HTTPS/Digest,
large-file stress or desktop interaction check. P4, schema, pins and versions
are unchanged. Reusable fixture: `.github/scripts/calibre-download-proxy.py`.
Full evidence: `/tmp/YabrDownloadReadP3/verification.json`; Chinese report:
`/Users/peterlee/.codex/visualizations/2026/11/05/01a1ab4c-32a7-7430-9886-27e16f7272a6/download-read-p3/report.html`.

## First Book Calibre Connection P2 (2026-11-05, branch)

`codex/first-book-calibre-browse` starts at latest `main` `e196ff5a`, including
P1 file import merged in #132. Welcome's Calibre action opens the existing
connection form directly. **Add and Browse Library** saves through the existing
manager; one library opens directly, multiple libraries require an explicit
choice. Main waits for modal dismissal, then pushes that exact library's
existing Browse list. Settings retains its management behavior and P1 import
is unchanged. Cancelled/failed/stale probes cannot confirm or route.

Final validation: 960 unit tests (22 skips, two existing expected PDFKit
failures), five existing UI journeys, iOS/Catalyst builds; six isolated real
Calibre journeys across iPhone 17, iOS 15.5 iPhone 7 and iPad mini pass. A further
iPad run verifies stable landscape geometry, opens book detail and returns.
iOS 15's supplementary category menu could not be opened by the native harness;
its core connection/back paths pass. No physical-device, native HTTPS/Digest,
download/read or HTTP-error-page work. Details and evidence are in
[Shelf Modernization](history/shelf-modernization.md) and
`/tmp/YabrCalibreOnboarding/verification.json`.

## First Book File Import P1 (2026-11-05, branch)

`codex/first-book-file-import` adds welcome/empty-local-library file import,
reuses existing deduplication and Read, and handles picker callback ordering
and stale empty local-search caches. Final iPhone 17: 118 unit + 2 UI tests;
iOS 15.5: 118 unit tests; Catalyst build pass. Native EPUB/PDF/CBZ checks and
boundaries are recorded in [Shelf Modernization](history/shelf-modernization.md)
and `/tmp/YabrFirstBookImport/verification.json`. Independent read-only review
found no actionable issues.

## FolioReader 303f371 Remote Pin (2026-11-03)

App branch `codex/update-folioreaderkit-tap-fix`, based on `main` at
`db1c28a6` (PR #130 merged), updates only the FolioReaderKit master pin from
`75cca2e` to `303f371ae0beb79552af95fae4f827fb729ba72c`, upstream PR #26.
Every other package pin and the origin hash stay unchanged.

- The normal Xcode project resolves the clean remote `303f371` checkout,
  tree `1ab9dbbb493a1863fce0ad7500ef3a00775de9c2`, with locked versions and
  no local override. iOS build-for-testing and Mac Catalyst build pass.
- Remote-pin focused validation passes all 34 `FolioReaderProviderBookIdTests`
  and the FolioReader Recent/detail/history UI journey (35 tests total).
- `db1c28a6` has the same app file tree as the previously tested `3a5b388b`.
  Reuse the full 216-package-test, 946-unit-test/five-UI-journey, iOS 15.5 and
  actual native-touch verification below for the identical library tree;
  the full app suite was not repeated for this pin-only follow-up.
- Upstream PR #26's [CI run #45](https://github.com/drearycold/FolioReaderKit/actions/runs/41570700571)
  passed. No temporary UI-test probe/fixture, app Swift, schema or build-number
  change is included. Final remote-pin logs: `/tmp/YabrFolio303RemotePin/`.

## FolioReader 303f371 Tap Regression Verification (2026-11-03)

Verified FolioReaderKit master `303f371ae0beb79552af95fae4f827fb729ba72c`
(PR #26) through an exact Git archive and external workspace at
`/tmp/YabrFolio303f371`. App commit is `3a5b388b`; its formal remote pin stays
at `75cca2e`. No app/library code or package-lock changes were made.

- **Package, iPhone 17 / iOS 26.5:** all 216 tests pass. The nine new tests
  cover retaining a completed tap through the asynchronous JS check, hide and
  reveal, media exclusion, movement/scroll/page reuse, and real-WebKit HTML/
  XHTML radio/checkbox controls, including 2/24-image cycles whose image
  shrinks before the native hit-test result returns. CSS snapshot unchanged.
- **iPhone 7 / iOS 15.5:** all nine `ReaderTapTests` and
  `ReaderControlHitTests` pass using the same built test bundle.
- **App integration with the local 303f371 override:** iOS build-for-testing
  and Mac Catalyst build pass. Full iPhone 17 scheme: 946 unit tests (22
  skipped, two existing expected PDFKit failures), no unexpected failures,
  and all five UI journeys pass, including FolioReader open/page/close and
  reading-history entry points. Logs confirm the new gesture file compiled.
- **Actual native-touch follow-up completed:** on iPhone 17 / iOS 26.5,
  `FolioTouchInteractionUITests.testActualImageCycleAndOrdinaryTextTaps` passes
  (25.169 s, four native XCUITest coordinate taps). A temporary app copy adds
  only the EPUB fixture and read-only UIKit/DOM observation; all FolioReaderKit
  production sources remain byte-identical to `303f371`. No JS click or direct
  toolbar mutation is used. The five captured states are: image 1 / 160 px /
  bars visible; image 2 / 40 px / bars still visible; an ordinary-text tap at
  the same screen point hides bars; another restores them; tapping image 2
  cycles back to image 1 with bars preserved. Screenshots visually confirm
  the image and toolbar changes. The earlier desktop CUA `noWindowsAvailable`
  error affected that input method; XCUITest completes the actual interaction
  validation. No physical-device or iPad run this round.
- Native UI test, five screenshots and state attachments:
  `/tmp/YabrFolio303f371/TouchHarness/Touch-303f371.xcresult`,
  `TouchHarness/Evidence/` and `TouchHarness/touch-states.json` under the same
  root. Test-only app/probe/UI-test code stays in the temporary directory;
  no application/library code or formal dependency pin is changed.
- Logs, xcresults, test summaries and fixture:
  `/tmp/YabrFolio303f371/verification.json`.

## FolioReader Embedded Video Remote Pin (2026-11-02)

App branch `codex/update-folioreaderkit-video`, based on `main` at `a0366c2e`,
takes FolioReaderKit [PR #25](https://github.com/drearycold/FolioReaderKit/pull/25)
merged to `master` as `75cca2e4a57e56f48448eac395a6454d15933a0f` (was
`d82f388`). Its tree is identical to the tested video branch `69936c6`.
Only this pin changes; every other package and the origin hash remain unchanged.
No app Swift, persistence schema, marketing version or build-number changes.

- The normal Xcode project, without a local package override, resolves the remote
  checkout at `75cca2e`. Both builds use
  `-onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates`.
- iOS build-for-testing and Mac Catalyst build pass. Full iPhone 17 / iOS 26.5
  scheme: 946 unit tests (22 skipped; two existing expected PDFKit failures),
  zero unexpected failures, and all five UI journeys pass.
- Upstream video PR CI [run #42](https://github.com/drearycold/FolioReaderKit/actions/runs/41440302801)
  passed. The pre-merge package/manual regression and its iPad snapshot and
  iOS 18.5 limitations are recorded immediately below.
- Final remote-pin logs and result bundle: `/tmp/YabrFolioVideoPin/`.

## FolioReader Embedded Video Branch Regression (2026-11-02)

Verified FolioReaderKit `codex/embedded-video-support` at
`69936c697f6b13694143603432692b4a51c807f9` against app `1113148aa`.
An exact Git archive of the clean library branch was used through an external
workspace in `/tmp/YabrEmbeddedVideoRegression`; app source and its remote
`Package.resolved` pin remain unchanged.

- **iPhone 17 / iOS 26.5:** all 207 package tests pass, including real WebKit
  playback and seeking to 6 s for stored and Deflate video, byte ranges,
  cancellation/corruption, media visibility, and spread/tier bounds.
- **App integration:** iOS build-for-testing and Mac Catalyst build pass with
  the local video package and the app's other locked dependencies. Full iPhone
  scheme: 939 unit tests (22 skipped, two existing expected PDFKit failures),
  zero unexpected failures; all five UI journeys pass, including FolioReader
  opening, paging, closing and reading-history entry points.
- **iPad mini / iOS 26.5:** 206 package tests pass; the only failure is
  `ReaderStyleRenderingTests.testComputedStylesSnapshot`. A focused run on
  master `d82f388` produces the identical failure text: the existing
  `min-device-width: 600px` rule sets body hyphens to `none`, while the phone
  snapshot expects `auto`. CSS, the snapshot and its test are unchanged by
  the video branch. Do not re-record the phone snapshot to hide this.
- **Manual app check, iPad 26.5:** a temporary copy of the built app replaced
  only its mock EPUB resource with the branch's video sample. Inline video
  advances to 3 s; media taps keep reader chrome stable; returning from the
  background leaves playback paused without restarting. Native full-screen
  playback renders moving frames and exits back to the chapter. The linked
  Deflate chapter loads and plays after a landscape relayout.
- **Incomplete:** iPad / iOS 18.5 stalled on the test helper's plain-HTML
  WebKit warm-up, before reader or video scripts loaded; interrupted, with
  logs and a WebContent process sample retained. No physical-device or iOS
  15 run, nor the complete manual rotation/background matrix. Native seek
  was not conclusive manually; automated real-WebKit seek passed on both
  iPhone and iPad.
- Logs, xcresults, baseline comparison and machine-readable summary:
  `/tmp/YabrEmbeddedVideoRegression/verification.json`. Initial build attempts
  hit SPM caches missing master `d82f388`; an isolated cache supplemented from
  the local library repo resolved it. No application/library code was changed.

## Realm Schema Independent of App Build (2026-10-30)

- `DatabaseSchema.version` in `Models/Persistence/DatabaseService.swift` is now
  an immutable, independently maintained schema version, starting at **148**.
  Build 148 previously opened production databases at schema 148, so using the
  old default 147 would downgrade existing main and server-scoped Realms.
- Production setup no longer reads `YabrAppInfo.shared.build`; test setup no
  longer mutates the production schema constant. All production Realm paths
  use the same constant. Build-only releases need no schema bump; schema/data
  migrations increment it and add the appropriate migration handling.
- Updated AGENTS.md and TestFlight workflow comments. Regression tests cover
  test-configuration isolation and preserving saved data from schemas 147/148.
- Validation: iPhone 17 focused suites `DatabaseBootstrapperTests`,
  `DefaultServerScopedRealmConfigurationProviderTests`, and
  `MockAppContainerFactoryTests` passed (20 tests, zero failures), using locked
  remote package versions and existing Xcode caches. Swift parse and
  `git diff --check` passed; no new Realm usage in views. Full suite and
  Mac Catalyst build were not run for this scoped change.

## TestFlight Automatic Upload Build Numbers (2026-10-31)

- `.github/workflows/testflight.yml` enables `manageAppVersionAndBuildNumber`.
  Xcode manages build numbers at export/upload; no build-bump PR is needed.
  Marketing version stays **0.2.9**, source build **148**, Realm schema **148**.
  Installed Settings already reads the packaged build via `YabrAppInfo`.
- Actions summary labels the source archive version and separately reads the
  uploaded version/build from `DistributionSummary.plist`. Missing/incomplete
  summary emits a warning without marking an already-successful upload failed.
- Local validation passed: YAML parse, all embedded shell syntax, export plist
  automatic-management flag, and summary handling with XML/binary plists,
  adjusted build 149, missing file and incomplete metadata. `git diff --check`
  passed. Cloud upload succeeded on 2026-10-31 in Actions run 41174759689;
  App Store Connect confirms **0.2.9 (149)**, so automatic build management works.
  The upload destination did not produce `DistributionSummary.plist`, and the
  summary reporter emitted its intended warning. Actual build reporting from
  upload logs/App Store Connect remains a workflow follow-up.

## App Store iOS 1.5 Submitted (2026-10-31)

- User requested formal App Store submission/publication after TestFlight.
  Existing public version is 1.4; the existing **1.5** draft accepted the latest
  **0.2.9 (149)** build without rebuilding or changing source marketing version.
- Selected build 149, saved English update notes covering EPUB page turns and
  position restoration, PDF reading, calibre browsing/offline search/sync, and
  stability. Completed the required updated age-rating questionnaire (16+,
  17+ on pre-26 systems), retaining unrestricted web access and declaring ads.
  User handled Apple login and confirmed the developer agreement was accepted.
- App Store Connect visibly confirmed **1 Item Submitted** and **Waiting for
  Review**. Existing automatic release after approval and immediate rollout
  settings were retained. No macOS version was submitted.
- Review submission: https://appstoreconnect.apple.com/apps/1592052131/distribution/reviewsubmissions/details/6538baa8-5cc1-42fc-9067-8ac27d39b871

## App Store 1.5 Review Feedback (2026-11-02)

- Verified in App Store Connect and Apple's email: **Rejected**, one message
  at 17:13 Asia/Shanghai, for **5.1.1(iv)**. Reviewed on iPad Air 11-inch (M3),
  version 1.5/build 149. User denies ATT tracking, then sees a GDPR prompt
  asking for tracking permission again in the same flow.
- Apple says to respect the ATT denial; either revise the later consent wording
  to distinguish data collection from tracking, or show GDPR before ATT. No
  tracking may occur before permission. Region-specific behavior must be
  documented and reproducible for review.
- Apple explicitly offers bug-fix approval now with resolution in the next
  update: request it by replying; no new upload/resubmission is needed for that
  path. Alternatively fix and resubmit. No reply or new submission has been
  sent; user has only requested tracking/reading the feedback so far.
- Two screenshot attachments are listed: Screenshot-1102-091143.png and
  Screenshot-1102-091208.png. Original review-submission URL above is unchanged.

## App Store Privacy Consent Fix (2026-11-02, in progress)

- User chose to fix and resubmit. `codex/fix-privacy-consent-flow` starts at
  main 1113148a. Root cause: `MainView` requested ATT before UMP/GDPR, and ad
  views could load independently of consent completion.
- `AdvertisingConsentManager` now serializes UMP update/form → ATT only if
  not determined → Mobile Ads initialization. Its published readiness gates
  shelf banners/native/fallback ads and Folio banners/interstitials. Duplicate
  triggers are ignored; consent errors keep ads blocked even with cached consent.
- Removed the extra tracking explainer and replaced Settings' production UMP
  reset with the supported privacy-options form. Simulator-only DEBUG arguments
  `--consent-debug-eea --consent-debug-reset` reproduce an EEA first consent;
  release builds always use UMP's real region/consent state.
- Regression proof: old ATT-first order fails four of the five initial tests;
  corrected order passes. Final iPhone 17 focused run: 49 tests pass (six consent,
  32 MainViewModel, 11 ad layout), including respecting existing ATT decisions.
  iOS 15.5 focused consent/ad-layout run: 16 pass. CI/upload/resubmission pending.
- Final privacy-options edge case: users can change consent even if ads never
  became ready; the same ATT/SDK gate is used afterward, and SDK initialization
  happens once. All seven final consent tests pass, including recovery after
  consent first disallows ads. Native Safari input was unreliable; the user
  signed in to the in-app browser and review notes are saved there. Live EEA
  form check hit a Google network error locally; ads correctly stayed disabled.

## FolioReader Chapter-Swipe Container Snap (2026-10-30, app integration)

FolioReaderKit [PR #24](https://github.com/drearycold/FolioReaderKit/pull/24)
merged to `master` as `d82f38830598af1656a4cbb31800802a9bdd0d0f`.
App branch `codex/update-folioreaderkit-swipe-fix`, based on `main` after #126,
takes that merge in `Package.resolved` (was `2af77f7`). Every other pin and the
origin hash stay unchanged; resolution's incidental AEXML 4.7.1 was restored
to the existing 4.7.0. Build the normal Xcode project with remote packages.

- **Symptom:** portrait iPad mini (A17 Pro), iOS 18.5, user recording:
  at 2.328–2.412 s content jumps back by about 251 recording pixels
  (125.5 pt at 2x). Workspace toolbar, top edge and text layout stay fixed;
  a later cancelled swipe returns smoothly.
- **Confirmed through callbacks:** `pageDidLoad` for the neighbour exposed by
  a held 125.5 pt drag reset the collection offset to zero. An unchanged-size
  controller layout snapped intermediate offsets on both axes, before and
  after the midpoint. The original code fails five assertions in the four
  new `ChapterContainerLayoutTests`.
- **Library fix:** `Center/SubViews.swift`, `updateSubviewFrames()`, realigns
  only for a changed page size, retaining the chapter before changing geometry.
  Indicator/scrubber frames still update on every call. Explicit navigation
  and direction changes position the collection separately. No app Swift,
  CSS, gesture, provider API or persistence changes.
- **Library CI follow-up:** the first PR run passed the four new tests but
  timed out in `TieredPagesTests.testRepeatedRotationsKeepTheScreen` waiting
  for viewport 744×1080. `readerChapter` now hosts pages in visible windows
  until main-actor teardown, with automatic scroll insets disabled. The
  generic loader stays detached so its mid-test release check remains valid.
  Timeouts, rotation counts and assertions are unchanged.
- **Upstream verified:** [CI run #40](https://github.com/drearycold/FolioReaderKit/actions/runs/41045322582)
  passed all 196 tests and both Example builds. The four swipe regressions
  pass on iPhone 17 and iPad mini; the rotation and release cases each pass
  five consecutive runs on iOS 18.5.
- **App verified with the remote merge and `-onlyUsePackageVersionsFromResolvedFile`:**
  normal project builds for testing and Mac Catalyst; iPhone 17 full scheme
  runs 937 unit tests with zero failures (22 skipped: contract tests without
  a server and the opt-in benchmark), and all five UI journeys pass.
  Logs confirm the remote checkout is at `d82f388`, and the compiler uses it.

## FolioReader Reopens Chinese Books at the Chapter Start (2026-10-29, branch)

Branch `claude/folioreaderkit-cfi-unicode-ids`, based on `main` after #122. It
takes FolioReaderKit `2af77f7` (drearycold/FolioReaderKit#23) in
`Package.resolved`.

- **The bug:** an EPUB made by pandoc names sections after their headings, so a
  Chinese book's ids are Chinese (`<section id="共通线">`). FolioReader records a
  position as a CFI asserting them, e.g.
  `epubcfi(/8/2/4/2[共通线]/12[id_00_common_02a-第二章]/30/2/1:35)`. On reopening,
  `getAnchorOffset` couldn't parse it: readium-cfi-js accepts only ASCII in an
  assertion (`[a-z] [A-Z] [0-9] - _ . %`; readium-cfi-js#73, archived, unfixed)
  and decodes percent-encoding before parsing. It answered 0, `handleAnchor`
  took that for the start of the chapter, and the book reopened at the top of
  the chapter file. A table-of-contents jump worked: it goes by element id.
  Seen on the iPad mini (A17 Pro) simulator, iOS 18.5, with
  `Calibre-Gaming - 101.epub`; any device and book with non-ASCII ids is the same.
- **Not the save:** the saved CFI was right (it resolves against the book's file
  to where the reader was closed). EPUB CFI 1.1 (2.2) allows any Unicode in an
  assertion, and HTML ids may be Chinese.
- **Found with** FolioReader's `.htmlStyling` debug output
  (`Views/FolioReaderView/Configuration.swift`, commented out), which prints the
  page's JS messages, including `getAnchorOffset partialCFI … error`. FolioReader
  logs with `print`: launch with
  `SIMCTL_CHILD_NSUnbufferedIO=YES xcrun simctl launch --stdout=<container>/tmp/stdout.log`
  (the simulator can't write to the session scratchpad).
- **The fix, in FolioReaderKit #23:**
  - `readium-cfi.umd.js`: the `character` class (`peg$c59`) also takes
    `\u0080-\uFFFF`. A local patch of the bundled, archived library,
    noted in its CLAUDE.md.
  - `getAnchorOffset` answers an empty string (nil in Swift) when it can't find
    the target, not 0, and a reopen whose CFI doesn't resolve falls back to the
    position's recorded offset and progress (`handleAnchor`'s `onFailure`).
  - Tests in `BridgeScrollPositionTests`; checked in the app on the book: it
    reopens at 第三章, where it was closed.
- **Probably the same:** highlights injected by CFI (`injectHighlight`) in such
  books; not checked, the book had none.
- **Alternatives looked at (2026-10-29):** foliate-js `epubcfi.js` (MIT,
  maintained, Unicode assertions, `NodeFilter` to skip `<highlight>`, calibre
  helpers) is the candidate to replace readium-cfi-js and its bundled jQuery
  later; saved CFIs must resolve to the same places. epub.js's `EpubCFI` is
  stale, and epub-cfi-resolver is AGPL.
- **Verified with the new pin (iPhone 17):** full scheme, 937 unit tests, 0
  failures, 22 skipped; the 5 UI journeys pass; Mac Catalyst builds. Built with
  `-onlyUsePackageVersionsFromResolvedFile`, and no other pin moved.

## Browse: Failures, Metadata Batches, Category Fields (2026-10-16, branch)

Branch `claude/browse-failures-offline-cache`, based on `main` after #121. Three
Browse fixes found on 2026-10-14, one commit each.

- **The bug:** a library whose search failed never got merge offsets in "all
  libraries" mode, and `getLibraryLoadingCount` counted a library without
  offsets as loading. So with a server down, Browse said "Loading books..." /
  "Still searching N libraries" forever. No view read `LibrarySearchStatus.error`.
- **Loading comes from the status now.** A library is loading while its status
  says so; offsets are only the fallback when it has no status.
- **A failed library shows its search cache** (`UnifiedSearchService`):
  - `ActiveSearch.libraryResults` keeps each library's books with their source:
    this search's answer, or the cache until it arrives and when it fails.
  - `cachedResult(for:key:)` reads the cache under the URL the server is
    reached by, else the newest other source. An unreachable server is looked
    up by its base URL, though its books may have been read through its public
    one.
  - The status says `fromCache`, and the merge treats the failed library as
    complete (`totalNumber = books.count`), so it doesn't stop the merge for the
    other libraries.
- **The cache shows before the server answers:** `triggerSearch` merges and
  emits the cached books with the statuses loading, then searches. A refresh no
  longer blanks the list.
- **Superseded searches:** `ActiveSearch.searchId` drops a replaced search's
  results and its `finishSearch`, which used to clear the newer search's loading
  flags. `triggerSearch` and `handleLibrarySearchResult` do their awaits first,
  then read, change and store the search without suspending.
- **UI:** the empty list says "Couldn't search <library>: <error>"; the footer
  adds ", N failed" or "Couldn't search N libraries"; the Libraries popover
  shows each library's error, or "Showing saved results".
- **Tests:** four in `UnifiedSearchServiceTests` (a failed library's cache
  doesn't hold others back; no cache, all-libraries mode, isn't loading; an
  unreachable server's other-URL cache; the cache before the answer). Each
  fails against the old code (checked by reverting the fix).
- **Verified (iPhone 17):** full scheme, 928 unit tests, 0 failures, 21 skipped;
  the 5 UI journeys pass; the Mac Catalyst build succeeds.
- **Category filters search calibre's field (2026-10-16, same branch).** They
  used the category's name, lowercased, as the field. calibre names categories
  in the server's language: with `CALIBRE_OVERRIDE_LANG=zh_CN`, `作者:"=Test
  Author"` finds 0 books (HTTP 200), `authors:` finds 1.
  - `CalibreLibraryCategory.field` decodes the field from the category's URL
    (`/ajax/category/617574686f7273/…` is `authors`; `#col`, `@usercat` and
    `search` too).
  - `CalibreLibrary.categoryFields` (name → field) is filled by the sync's
    categories step (`applyCategoryFields`) and persisted as
    `CalibreLibraryRealm.categoryFieldsData`: **schema 147**. Until a library's
    next sync it's empty, and filters fall back to the old rule.
  - `CalibreLibrary.searchField(forCategory:)`: calibre's field, else a custom
    column's, else the name lowercased, which suits the app's own English keys
    ("Authors", "Tags", "Series" from Discover, the context menu and the book
    list). `isRatingField` replaces the `"Rating"` name check.
  - The category sort rule (series by index, authors and publisher by date)
    goes by field (`CalibreLibraryManager.searchField(forCategory:)`).
  - Filters stay keyed by the category's name: one name merges across
    libraries, and two servers in different languages give two filters.
  - Tests: field decoding and lookup (`CalibreDataSplitTests`), the query
    (`CalibreServerServiceTests`), the sync keeping the map
    (`CalibreLibraryManagerTests`), the Realm round trip, the sort rule, and
    contract test `testACategoryFilterFindsTheCategorysBooks`, which passes
    against a zh_CN server and fails there with the old rule (0 vs 1 books).
- **Verified after all three (iPhone 17):** full scheme, 937 unit tests, 0
  failures, 22 skipped; 5 UI journeys pass; contract tests 21 of 21 against an
  English calibre 9.11, no 404; Mac Catalyst builds.
- **Metadata in batches (2026-10-16, same branch).** calibre refuses a request
  line over 8 KB (`max_header_line_size`): 1,300 five-digit ids in one
  `ajax/books` URL pass, 1,500 get 400. Browsing put every loaded id in one
  request, ignored the failure and saved the cache with the new generation.
  - `CalibreServerService.booksMetadataBatchSize` (200).
    `LibrarySearchService.refreshMetadata` reads in batches, one after
    another. When a request doesn't arrive, the cache keeps the generation it
    had, so the next search reads the books again; an answer that can't be
    decoded doesn't count, as rereading won't help.
  - `CalibreBookManager.getBooksMetadata(request:)` splits a longer list (a
    large shelf's) into batches. Its annotations request lists each book and
    format in the path, so it has the same limit.
  - Tests: `testLibrarySearchReadsMetadataInBatches`,
    `testAFailedMetadataBatchLeavesTheBooksToBeReadAgain`,
    `testALargeShelfIsReadInBatches`.

## Library Sync Without a Book List (2026-10-14, #121)

Branch `claude/retire-library-sync-book-list`, based on `main` after #120,
merged as #121. This carries out the decision in "Calibre Contract Coverage"
below.

- **`CalibreLibraryManager.syncLibrary(request:)` now** reads, with the
  requests browsing makes:
  - `CalibreServerService.getLibrarySummary`: `ajax/search` with
    `sort=last_modified&sort_order=desc&num=1`, then
    `ajax/books?ids=<newest>&category_urls=false`.
    - The book count (`num_books_without_search`) goes to
      `librarySyncStatus.cnt`, which a sync no longer resets.
    - The newest `last_modified` is kept only if newer. If it isn't, but the
      count differs from the last summary's, the generation moves 1 ms past
      what it had (`applySummary`): a deleted book changes no other book.
    - The custom columns come from that book's `user_metadata`
      (`CalibreBookUserMetadataColumn`). Changes are saved on the library and
      published as `.library`.
  - `getLibraryCategories(library:)`, then `refreshCategoryCaches`, which now
    returns the first category that failed.

  `isSync` covers the summary only, so a category refresh the user asks for
  meanwhile isn't dropped. The status reads "Success" or the summary's error
  once the summary is in; a failed categories request or category then sets
  `isError`, unless the summary failed or a newer sync started. A library
  removed meanwhile gets no categories. Nothing is inferred from an answer that
  didn't arrive.
- **Removed:**
  - the book list: `syncLibraryResult` / `syncLibrary(resultPrev:)`,
    `saveBookMetadata` (`.save`, `.updateDeleted`, `.complete`), and
    `BookRepository.saveBookSyncRecords`, `findDeletedBookIds`,
    `countAndNeedUpdateBooks` and `deleteBooks(library:ids:)`;
  - `getCustomColumns*`, `getLegacyCustomColumns*` and
    `syncLegacyLibraryResult`, so sync makes no `cdb` request at all;
  - the types `CalibreCdbCmdListResult`, `CalibreSyncLibraryResult`,
    `CalibreSyncLibraryBooksMetadata` and `BookMetadataSyncRecord`, and
    `CalibreSyncStatus.upd`, which nothing filled any more;
  - the last-modified probe stream (`publishProbeLibraryLastModifiedRequest`,
    `startProbeLibraryLastModifiedTask`). `probeServer` ran `syncLibrary` *and*
    a probe for each library, and `syncLibrary` now reads `last_modified`
    itself;
  - `incremental` on `CalibreProbeServerRequest` and
    `probeServersReachability`, and `autoUpdateOnly` / `incremental` on
    `CalibreSyncLibraryRequest`.
- **Last-modified probe: replaced, not kept.** calibre's `cdb_run` answers 403
  to a user with per-library restrictions (checked against 9.11).
  `ajax/search` answers within the restriction.
- **Custom columns:**
  - `CalibreCustomColumnDisplayInfo` decodes leniently: a field that's missing
    or of another type is dropped. `useDecorations` is a Bool, as calibre
    stores it since 5.35; the older 0 / 2 read as false / true.
    `CalibreCustomColumnInfo` keeps the synthesized decoder, as only the app's
    own Realm JSON reaches it.
  - `normalized` is removed: nothing read it, and `ajax/books` doesn't give it.
    Realm keeps the JSON with the `cdb` key names.
  - `CalibreBookUserMetadataEntry` and `CalibreBookEntry.user_metadata` are
    removed: nothing read them (values come from the JSON itself), and the
    entry's required `table` was checked on every book.
  - Checked in calibre's source (`Cache._get_metadata`) and against a library
    of 2 books × 3 columns: every column is on every book, valued or not.
- **Deletions are per book, and only shown.**
  `CalibreBookManager.recordMetadataAnswers` keeps `librarySyncStatus.del`
  (null answers) and `err` (unreadable ones); a book that's read leaves both.
  It hears from `getBooksMetadata` (shelf, Book Detail) and from browsing
  (`LibrarySearchService`'s `onMetadataAnswers`, set in `AppContainer`).
  Settings says "unavailable on server", as a restricted user gets null too.
  - The remove-deleted toolbar button and `removeDeleteBooksFromServer` are
    gone: calibre also answers null for a book a restricted user may not see
    (`ajax.books`, `allowed_book_ids`).
- **"Available when Offline" removed:**
  - the toggle, `LibraryViewModel.setAutoUpdate` and the play icons;
  - `CalibreLibrary.autoUpdate` and `CalibreLibraryRealm.autoUpdate`. This is
    **schema 146**: `CFBundleVersion` in both Info.plists and four
    `CURRENT_PROJECT_VERSION`s;
  - the `/realm` search source for such libraries;
  - `buildProbeLibraryTask`'s `/realm` fallback, which now needs a reachable
    URL, and with it the service's `librarySyncStatus` accessor.
- **Old non-shelf `CalibreBookRealm` records stay.** Search caches point at
  them, a stale library generation refetches every listed book, and
  `writeMetadataEntries` creates records on demand. Removing a library deletes
  its records.
- **Deleted books and the caches:** deleting a book changes no other book's
  `last_modified`. The changed count moves the generation instead, but the
  count lives in memory (`librarySyncStatus.cnt`), so the first sync after a
  launch has nothing to compare: a deletion made while the app was closed shows
  after the next edit or a forced refresh. `total_num`
  (`shouldRebuildAfterIncrementalFetch`) is only checked when a page is
  fetched incrementally.
- **Review fixes (2026-10-14):**
  - `LibraryViewModel.setDiscoverable` also sets the manager's copy, which
    whole-library saves (`applySummary`, hide, restore) wrote back.
  - Summary, categories and the library probe use absolute paths through
    `makeEndpointURL`, like every other request, and `SortCriteria.Modified`.
  - AGENTS.md lists the restricted user's `cdb` 403 as checked by hand, not
    pinned.
  - `autoUpdateOnly`'s comment now says every probe passes true; the
    DSReader Helper branch it guards is dead, as on `main`.
- **Tests:**
  - **Contract: 20 (was 18).**
    - The three full-sync tests are removed.
    - The probe and legacy-column tests now read `getLibrarySummary`, with no
      `XCTExpectFailure` left.
    - New: a restricted user's summary, a restricted user's `null`, a whole
      sync through the manager, and per-book deletion.
    - The seed adds `contract-restricted` (`title:"=No Such Book"`), so reseed
      from an empty DIR.
  - **Mocks:**
    - `MockURLProtocol.answer(_:)` answers exact paths and logs any other. The
      library and server manager tests and the service tests use it.
    - New: `testABookCalibreAnswersNullForIsListedNotRemoved`,
      `testAFailedSummaryIsReportedAndChangesNothing`,
      `testPersistMetadataEntriesReportsANullEntryAsDeleted`,
      `testCalibreCustomColumnDisplayInfoToleratesAnEmptyOrUnexpectedDisplay`,
      `testAChangedBookCountMovesTheGenerationOnce`,
      `testAFailedCategoryIsReported`,
      `testARemovedLibraryIsNotSavedOrGivenCategories` and
      `testBrowsingListsABookCalibreAnswersNullForAndClearsOneItHas`.
- **Verified (iPhone 17):**
  - After the review fixes: 924 unit tests, 0 failures, 21 skipped; contract
    tests 20 of 20 against a fresh calibre 9.11 seed, no 404 in its access
    log; Mac Catalyst builds. UI journeys not rerun.
  - Before them, the full scheme ran 920 unit tests with 0 failures and 21
    skipped (the 20 contract tests, with no server running, and the
    benchmark). The 5 UI journeys passed.
  - The contract tests passed 20 of 20, twice, against a freshly seeded calibre
    9.11, and calibre's access log had no 404. The only `cdb` request left is
    `set_metadata`.
  - The Mac Catalyst build succeeds.
  - `/tmp/YabrSourcePackages` was gone again, so packages and derived data
    were in the session scratchpad.

## PDF Outline Lookup Takes 1-Based Pages (2026-10-14, branch)

Branch `claude/mystifying-galileo-86577e`, based on `main` after #119.

- **Bug:** `YabrEBookReaderPDFMetaSource.yabrPDFOutline(_:for:)` handed its
  page to the 0-based `PDFDocument.page(at:)`, but every caller passes a
  1-based `pageRef?.pageNumber`. It read the next page's text, so a chapter's
  last page reported the next chapter and the document's last page none. That
  reached:
  - PDF bookmark titles (`"<outline label>, p. N"`,
    `PDFBookmarkManager.addBookmark`);
  - bookmark and highlight list sections and their headers
    (`YabrPDFBookmarkList`, `YabrPDFHighlightList`,
    `YabrPDFTableViewController`);
  - search results (`"Page N - <outline label>"`, `YabrPDFSearchList`).
- **Fix:** `page(at: page - 1)`, nil below 1; the `YabrPDFMetaSource`
  protocol documents the base. Callers checked, all 1-based:
  - bookmarks: `currentDestination.page?.pageRef?.pageNumber`;
  - highlights: `PDFHighlight.PageLocation.page`, from
    `selectionPage.pageRef?.pageNumber` in `PDFAnnotationManager`, read back
    with `page - 1` in `PDFReaderSurface`;
  - search hits: `pageRef?.pageNumber`;
  - list section keys: an outline destination's `pageRef?.pageNumber`.
- **Not changed:**
  - Bookmarks saved before the fix keep their titles. On a chapter's last
    page that is the next chapter's name. Renaming them would be a retitle: a
    tombstone plus a new record on calibre.
  - The lookup needs a text layer, so a scanned page has no outline and its
    bookmark is titled `"Page N"`.
- **Tests:** `YabrEBookReaderPDFMetaSourceTests` (new):
  - a 7-page `UIGraphicsPDFRenderer` PDF with chapters starting on pages 1, 4
    and 6, read back through `dataRepresentation()` and hosted in a
    `YabrPDFView`;
  - checks the first and last page of each chapter, the document's last page,
    the section key (the chapter's start page), and pages 0, -1 and 8.

  With the old lookup it fails 6 assertions (pages 3, 5, 7, both section keys,
  and page 0, which read page 1).
- **Verified** (iPhone 17): the full scheme ran 919 unit tests with 0
  failures and 20 skipped (the 19 contract tests, no server running, and the
  benchmark), plus the 5 UI journeys. The Mac Catalyst build succeeds.
  `/tmp/YabrSourcePackages` was gone again, so packages and derived data were
  in the session scratchpad.

## Unique Bookmark Titles, Merged by Title (2026-10-14, branch)

Branch `claude/unique-bookmark-titles`, based on `main` after #118.

- **Problem:** calibre keeps one bookmark per title for each book, format and
  user. The app merged by `pos`, and the PDF reader titled bookmarks with the
  chapter's outline label, so two in one chapter collapsed on the server. Also:
  - removals never reached the server (uploads used `excludeRemoved: true`);
  - remote PDF (`yabrpdf`) bookmarks were never imported (the merge took only
    `epubcfi`);
  - every format's list merged into the book's single pool.
- **Titles:** `RealmAnnotationRepository.saveBookmark` makes a title unique
  among the book's visible bookmarks (`BookmarkMerge.uniqueTitle`: `T #2`,
  `#3`…, calibre's viewer style). A retitle is a tombstone of the old title plus
  a new record, so the old title is removed on the server too. PDF titles are
  `"<outline label>, p. N"` (`PDFBookmark.title`). `getBookmark(byPos:)` skips
  removed ones.
- **Merge:** `BookmarkMerge.plan` (`Models/Domain/BookmarkMerge.swift`):
  - calibre's bookmark of a title matches the local one with that title at the
    same position, and the newer wins (ties within 2 ms go to the server, as in
    calibre);
  - one at another position is a different bookmark: it keeps the title and
    the local one is retitled, so nothing is lost. That covers legacy
    duplicates and two devices' same-titled PDF bookmarks. The trade-off: a
    bookmark moved in calibre's viewer (re-added under an existing title)
    stays behind here under a new title;
  - `syncBookmarks(entries:forBookId:posType:)` returns exactly the entries to
    upload, tombstones included (calibre merges, so the rest stay home).
    `BookMetadataSyncWorker` uploads those.
- **Per format:** `Format.bookmarkPosType` (EPUB `epubcfi`, PDF `yabrpdf`, CBZ
  none). Each format merges and uploads only its reader's bookmarks. Without
  this, two formats disagreeing about a title's position would rename a bit
  more on every sync. FolioReader's provider now lists `epubcfi` bookmarks only.
- **Tolerance found by the contract test:** the planner first used the old
  0.1 s "same edit" window. An edit within 0.1 s of the last upload then tied,
  and the server's visible copy revived it. Now 2 ms
  (`testAnEditSoonAfterASyncIsNewer`).
- **Tests:** `RealmAnnotationRepositoryTests`:
  - the pos-era tests are rewritten;
  - two-device tests run against a simulated calibre merge: PDF bookmarks on
    one page, legacy duplicates, removal not resurrected, retitle not
    duplicated, one title at two places, a removal elsewhere, per format;
  - plus title and page helpers.

  Worker, Folio provider and PDF title tests too. Contract:
  `testTwoDevicesKeepEachBookmark` (19 contract tests). Mutation-checked:
  dropping tombstone uploads and the collision retitle fails the removal,
  retitle and one-title-two-places tests.
- **Verified** (iPhone 17, calibre 9.11 contract server running): the full
  scheme ran 916 unit tests with 0 failures and 1 skipped (the benchmark),
  including all 19 contract tests, plus the 5 UI journeys. The Mac Catalyst
  build succeeds. Packages and derived data were in the session scratchpad
  (`/tmp/YabrSourcePackages` was gone).
- **Found, fixed after:** `yabrPDFOutline(_:for:)` passed the 1-based page to
  the 0-based `page(at:)`, so a chapter's last page reported the next chapter
  (titles and list sections alike). See "PDF Outline Lookup Takes 1-Based
  Pages".
- **Not changed:** bookmarks at one position are one to FolioReader
  (`removeBookmark(pos:)` removes all of them); legacy cross-format entries on
  the server (PDF bookmarks in an EPUB's list) are left alone.

## Server Sessions Follow Password Changes (2026-10-14, branch)

Branch `claude/session-credentials`, not yet pushed.

- **Bug:** `CalibreServerService.urlSession(server:timeout:qos:)` cached one
  `URLSession` per `CalibreServerURLSessionKey`, whose equality came from
  `CalibreServer` (`baseUrl` + `username`), and never dropped any. The session's
  `CalibreServerTaskDelegate` keeps the password it was created with. After a
  password change in Settings, every request answered calibre's challenge with
  the old password until the app restarted. Found by the contract tests.
- **Fix:** the key also compares and hashes `server.password`. `CalibreServer`'s
  own `==`/`hash` are unchanged, because the rest of the app identifies servers
  by them. On a cache miss, the same server's sessions for any other password (all
  timeouts and QoS) are retired, so a server keeps sessions for one password: the
  newest one asked for. `retireSessions(for:)` drops a removed server's sessions,
  and `CalibreServerManager.removeServer` calls it.
- **Why leases:** creating a task in an invalidated session raises
  `NSGenericException` ("Task created in a session that has been invalidated"),
  which crashes the app. This was checked with a scratch program; invalidation
  takes effect synchronously. `withURLSession(server:…)` counts a lease for the
  whole request, and a retired session is invalidated
  (`finishTasksAndInvalidate`) only when its last lease ends. `validatedData`
  and `LibraryCategoryService`'s non-HTTP branch use it. `urlSession(server:)`
  is still there for tests and `DSReaderHelperConnector.urlSession` (only used by
  tests).
- **Known transient:** after an edit, in-memory copies of the server holding the
  old password (books in `booksInShelf`, for example) and fresh copies alternate
  retiring each other's sessions. That costs new connections, but it is safe and
  stops once the old copies are gone. The mod-server probe of a candidate
  password retires the saved password's sessions the same way.
- **Not changed:** `CalibreServerManager.populateServers` stores `.permanent`
  credentials in `URLCredentialStorage.shared` at launch, and nothing updates
  them on an edit. Challenges are answered by the delegates, so they don't decide
  what is sent. Only the Digest path is covered by the contract tests.
- **Tests:** `CalibreServerServiceTests` (4 new):
  - different passwords get different sessions, and each delegate has its own
    credential;
  - a new password retires and invalidates the old password's sessions;
  - a leased session stays usable until its request ends;
  - `retireSessions(for:)` invalidates a server's sessions.

  `CalibreServerManagerTests.testRemoveServer` checks the sessions are retired.
  `CalibreServerContractTests` replaces the unknown-user workaround with
  `testAWrongPasswordIsReportedByTheProbe`: contract-writer with a wrong password
  after the right one's session is cached, then the right password again. It
  keeps `testAnUnknownUserIsReportedByTheProbe`, so there are now 5 contract
  tests.
- **Verified** (iPhone 17, calibre 9.11 contract server running): the full
  unit suite ran 888 tests with 0 failures and 1 skipped (the benchmark), and
  all 5 contract tests ran. The scheme also ran the 5 UI journeys, which
  passed. The Mac Catalyst build succeeds. On the pre-fix code (`ded54897`),
  `testAWrongPasswordIsReportedByTheProbe` fails: the wrong-password probe is
  reachable with no error.
- **Local build note:** `/tmp/YabrSourcePackages` was gone entirely, so the
  runs used package and derived-data directories in the session scratchpad.

## Highlight UUID Conversion Without UB (2026-10-14, branch)

Branch `claude/highlight-uuid-ub`, not yet pushed.

- **What:** `uuidFolioToCalibre` / `uuidCalibreToFolio`
  (`Network/CalibreServerService.swift`) no longer touch memory they don't
  own. The first wrote 16 bytes into a 1-byte `UInt8`; the second used
  `withUnsafeBytes`'s pointer after the closure returned. Both now go through
  `UUID.uuid` (`uuid_t`) and keep the pointer inside the closure.
- **Calibre's format** (checked in calibre's source and 9.11's `viewer.js`):
  a new highlight's `uuid` is `short_uuid()`, 16 random bytes (not a version-4
  UUID) in base64url without padding, 22 characters. The server merges
  highlights by exact `uuid` string (`merge_field_map` in
  `db/annotations.py`) and never validates it, so a changed encoding would
  duplicate highlights rather than fail.
- **Same output:** the known vectors in `CalibreHighlightUUIDTests` were
  computed with the old code (-Onone and -O) and match Python's
  `urlsafe_b64encode(uuid.bytes)` and calibre's own encoder. Old and new also
  agreed on 200k random UUIDs and 200k random 22-character calibre ids.
- **Changed:** a calibre `uuid` that doesn't decode to exactly 16 bytes now
  gives `nil`, and the sync skips that entry. Before, the code read past the
  buffer and returned a garbage, run-dependent id, which the sync stored.
- **Tests:** `CalibreHighlightUUIDTests` (8): known vectors both ways,
  lowercase input, 10k random round trips each way, invalid UUID strings,
  non-base64 and non-16-byte calibre ids.
- **Verified** (iPhone 17): full unit suite, 883 tests, 0 failures, 5 skipped
  (4 contract tests without a server, the benchmark). Mac Catalyst build
  succeeds.
- **Local build note:** most files under `/tmp/YabrSourcePackages` had been
  removed (directories left, mtimes 2026-10-14 00:00), so `xcodebuild` failed
  with "Could not resolve package dependencies … Package.swift doesn't exist".
  The run above used a fresh `-clonedSourcePackagesDirPath` and derived data.

## Branch Protection on `main` (2026-10-14)

- **Ruleset "Protect main"** (id 25044670, on the default branch). AGENTS.md
  "CI" has the rules:
  - a pull request is required, merged with a merge commit or squashed (squash
    added the same day; no rebase), with 0 approvals;
  - **iOS unit tests** and **Mac Catalyst build** must pass, and the branch
    need not be up to date with `main`;
  - force pushes and deletion are blocked, with no bypass actors (admins
    included).
- **Repository settings:** auto-merge is allowed, and head branches are
  deleted on merge.
- **Docs-only changes skip CI** since drearycold/YetAnotherEBookReader#115
  (merge commit `1af35ac9`). A **Detect changes** job runs
  `.github/scripts/changed-code.sh`; when every changed path is root Markdown
  or under `.agents/`, the three macOS jobs are skipped by their `if:`, which
  GitHub counts as passed. When in doubt it runs everything.
- **Not required yet:** **Calibre contract tests**. Add it to the ruleset once
  it has proved stable. Renaming a required job also needs a ruleset update.
- GitHub added `require_extra_approval_for_unattributed_changes: true` to the
  pull-request rule by default. It isn't documented publicly and didn't block
  #113. If a pull request unexpectedly needs a review, check it first.

## Calibre Contract Coverage (2026-10-14, `claude/calibre-contract-coverage`)

- **Tests:** `CalibreServerContractTests` has 18 tests (was 5), covering
  bookmarks, a read-only user, library sync (probe, full sync, custom columns,
  categories), metadata reads and writes, and downloads.
  `calibre-contract-server.sh` now seeds an int column `#read_progress` and
  prints the read-only user's variables. AGENTS.md "Calibre Contract Tests"
  lists what each pins.
- **Known bugs, pinned with strict `XCTExpectFailure`:**
  - the full sync's `/cdb/cmd/list/<key>` and `/cdb/cmd/custom_columns/<key>`
    answer 404 (since 88665ad6, April). The mocks match with `path.contains`,
    so they pass;
  - `CalibreCustomColumnDisplayInfo` requires `description`, which calibre
    omits (`"display": {}`).
  - The failure is swallowed (`syncLibrary(resultPrev:)` sets `errmsg`, not
    `isError`). The manager reports "Success" and marks every non-shelf book
    as deleted, which Settings' remove-deleted button would delete locally.
    `testAFailedFullSyncSaysSo` pins the swallowed error.
    - Run through `CalibreLibraryManager.syncLibrary(request:)` against the real
      server, the status read `isError: false, msg: "Success", cnt: 0,
      del: [1]`.
    - In one of three runs `del` came out empty, probably a background Realm
      not seeing the main-thread write (not investigated). So no strict test
      pins `del`.
  - That's why main seemed to work against the user's calibre 8.15: calibre's
    `/cdb/cmd/{which}/{version=0}` route is the same in v8.15.0 and v9.11.0
    (checked in calibre's source; not yet run against 8.15).
  - **Decision (2026-10-14, the user): retire the full library sync's book
    list** rather than fix it. Nothing user-facing reads its records:
    - Browse, Discover and search use `ajax/search` + `ajax/books`, and
      `writeMetadataEntries` creates records on demand.
    - V2 search (June) stopped using the local `file:///realm` source for
      remote "Available when Offline" libraries.
    - Keep categories, custom-column definitions, per-book deletion and the
      last-modified probe, moved out of `syncLibrary`.
    - Filed as the task "Retire the full library sync's book list". No need to
      run the tests against calibre 8.15: its `/cdb/cmd` route is the same as
      9.11's.
    - Done on `claude/retire-library-sync-book-list` ("Library Sync Without a
      Book List" above).
- **Found, filed separately:** calibre merges bookmarks by `title`, the app by
  `pos`, and the PDF reader titles bookmarks by chapter, so two in one chapter
  collapse on the server ("Give each PDF bookmark a title calibre can keep").
- **Found, not filed:**
  - a read-only user's 403 shows as "Authentication Failed";
  - `--url-prefix` is harmless against calibre itself (it answers bare paths
    too), so the prefix `makeEndpointURL` drops only matters behind a proxy.
- **Checked:** `parseLastModified` reads calibre's microsecond timestamps.
  Download sizes differ from `format_metadata` (calibre embeds metadata), which
  is harmless: the cache check uses mtime.
- **Not covered:** DSReader Helper, a GUI plugin that starts its own server in
  the calibre app; an older calibre version.
- **Verified locally** against a freshly seeded calibre 9.11 server: 18 run,
  0 unexpected failures. Only one calibre program can run per user, so stop the
  calibre app or another server first.

## Calibre Contract Tests (2026-10-14, merged)

**Merged to `main`** in drearycold/YetAnotherEBookReader#113 (merge commit
`61064448`, 2026-10-14). GitHub deleted the remote branch
`claude/calibre-contract-tests` on merge.

- **What:** `CalibreServerContractTests` (4 tests) run the app's own
  `CalibreServerService` against a real calibre-server. CI runs them in a new
  `calibre-contract` job, installing calibre `CALIBRE_VERSION` from the
  official dmg (cached). `.github/scripts/calibre-contract-server.sh` seeds and
  starts the server; `.github/scripts/pick-simulator.sh` is now shared by both
  simulator jobs. AGENTS.md "Calibre Contract Tests" has the commands and what
  calibre does.
- **Verified locally** (calibre 9.11, iPhone 17): all 4 pass. Without the
  server variables all 4 skip, which the CI job treats as a failure. The full
  unit suite wasn't rerun locally (no app code changed).
- **CI:** on the head commit `357da72b`, all three jobs passed, including the
  first run of **Calibre contract tests** with the calibre download and
  install.
- **Found:**
  - calibre stamps reading positions with its own clock. #107's "newer position
    from another device" compares epochs, so a device that read earlier but
    synced later (offline reading) is offered as newer and moves the reader
    back. Not fixed.
  - Sessions are cached per server URL and username, and their delegate holds
    the password: a changed password keeps the old one until relaunch. Filed as
    a separate task.
  - `uuidFolioToCalibre` / `uuidCalibreToFolio` read and write memory they
    don't own (UB that happens to work). Fixed on `claude/highlight-uuid-ub`
    ("Highlight UUID Conversion Without UB" above).
  - Positions need a calibre user: anonymously, uploads fail with HTTP 500.
- **Next:** DSReader Helper (`calibre-customize`), bookmarks, metadata
  (`cdb/cmd`), downloads, an oldest-supported calibre.

## FolioReaderKit 1c1a23a, One Page / Two Pages Kept, Schema 145 (2026-10-13, merged)

**Merged to `main`** in drearycold/YetAnotherEBookReader#109 (merge commit
`e41b4f4e`, 2026-10-13). The branch `claude/update-folioreaderkit` is deleted,
remote and local.

- **FolioReaderKit `196fcd5` → `1c1a23a` (033af35d).**
  - Two pages side by side in landscape on iPad (FolioReaderKit#14), with One
    Page / Two Pages in the page menu (preference `currentLandscapeSpread`).
  - Tiered pages for vertical writing on iPad (FolioReaderKit#15). They use the
    existing `.vertical` direction, so stored direction values don't change.
  - Kept-chapter and layout fixes (FolioReaderKit#16–#21).
  - Updating also moved four transitive packages. They were kept: all are
    within Readium's and FolioReaderKit's ranges, and the app uses no changed
    API.
    - CryptoSwift 1.9.0 → 1.10.0
    - Fuzi 4.0.0 → 4.0.1
    - SQLite.swift 0.15.5 → 0.16.0
    - SwiftSoup 2.13.3 → 2.14.1 (macOS minimum 12, the Catalyst target's)
- **A book's One Page / Two Pages choice is saved (b5572ae9, schema 145).**
  - The provider kept it in memory only: `FolioReaderPreferenceValue` saves a
    fixed set of fields.
  - `currentLandscapeSpread` is now in `FolioReaderPreferenceValue` and
    `FolioReaderPreferenceRealm` (`RealmProperty<Bool?>`), so per-book rows and
    profiles keep it.
  - `nil` is no choice: FolioReaderKit then uses
    `FolioReaderConfig.landscapeSpread`, as `.defaultVertical` means no scroll
    direction. Applying a value without a choice removes the key, so a book or
    profile without one doesn't keep an earlier one.
  - Schema 145: `CFBundleVersion`, `CURRENT_PROJECT_VERSION`,
    `DatabaseSchema.defaultVersion`. Optional column, no data migration; old
    rows read nil (test: `testFolioPreferencesSavedAtSchema144HaveNoLandscapeSpreadChoice`).
- **CI fix (660ffff2).** `IntegrationTests.testSearchToDownloadFlow` slept a
  fixed 0.5 s for a mock download and failed on the runner. It now waits for
  the file, bounded at 10 s.
- **Flaky tests, not fixed:**
  - `CalibreLibraryManagerTests.testRemoveLibrary` crashes the test host about
    1 in 26 runs (`-[NSIndexPath count]` or `-[__NSCFNumber count]` sent to
    `0x8000000000000000`).
    - It's `async` in a class that isn't `@MainActor`, so it writes
      `booksInShelf` off the main thread while `updateBook`'s main-queue
      publish writes the same dictionary.
    - Production callers (`removeLibrary`, `getBooksMetadata`) are
      `@MainActor`.
    - Fix: isolate the test to the main actor.
  - `IntegrationTests.testDatabaseInitialization` can hit
    `assertionFailure("Missing AppContainer environment")`
    (`AppContainer.swift`, `AppContainerEnvironmentKey`).
    - It happens only when the test repeats itself (`-test-iterations`):
      `tearDown` sets `AppContainer.shared = nil`, and the host app's SwiftUI
      then reads the environment default.
    - The normal order doesn't hit it.
- **Verified:**
  - CI green on `660ffff2`.
  - Locally: 871 unit tests passed, 1 skipped; Mac Catalyst builds.
  - Dropping the Realm write fails the three new round-trip tests.
  - A Debug build of `b5572ae9` (build 145) installed and launched on the iPad
    Pro 10.5 (iOS 17.7); no crash log after launch.
    - `devicectl device info processes` fails on that iPad (CoreDevice
      StreamingAction error); check `--domain-type systemCrashLogs` instead.
    - Its Realm is now at 145, so a pre-145 build can't open it. The data stays
      on disk; a 145+ build opens it again.
- **Not verified:** One Page / Two Pages in the running app on an iPad.
- **Network (2026-10-13):** `github.com` didn't resolve on this machine's
  network, so SSH fetch and push failed. `gh` worked through `HTTPS_PROXY`, and
  git did over HTTPS with
  `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push https://github.com/drearycold/YetAnotherEBookReader.git …`.

## Reading Positions: Picked, Synced, Newer (2026-10-13, merged)

**Merged to `main`** in drearycold/YetAnotherEBookReader#107 (merge commit
`96642147`, 2026-10-13). The remote branch
`claude/continue-reading-picked-position` is deleted.

- **Continue Reading opens the picked position (4bf995bf).**
  - The bug: ▶ in History opened this device's latest position, not the row's.
  - Mounting fell back to this device's latest same-reader position from the
    repository even on a first mount, and `openReader` reused an open tab.
  - Now `.readingPosition` and `.newerPosition` presentations are "picked":
    - they mount at their position until their reader records one;
    - they replace an open tab of the same book and reader.
- **FolioReader starts at the position it opened with (9a05a7a7).**
  - Found on the iPad: ▶ still opened this device's position for EPUBs.
  - `FolioReaderCenter.reloadData` asks the position provider where to go right
    after opening. `FolioReaderYabrReadPositionProvider` returned the
    repository's newest position from any device (`.latest`).
  - FolioReader saves its opening position on a background queue, so the newest
    was still this device's earlier position, another device's (Continue Here
    would jump anyway), or a closing tab's.
  - The provider now returns its own reader's position: `readerInfo.position`,
    then each one it saves (lock-guarded).
  - Readium and PDF read `readerInfo.position` directly and weren't affected.
- **Library sync pulls shelf positions (6a865830, reverted in 42cc937b:
  suspected performance problems on device; kept here for when it returns).**
  - calibre doesn't change a book's `last_modified` when a reading position or
    annotation is saved (`Cache.set_last_read_position` and
    `set_annotations_for_book` only write `last_read_positions` and
    `annotations`).
  - So `bookToUpdate` never includes a shelf book read only elsewhere.
  - At `.complete` of every sync, the library's shelf books are fetched with
    `getAnnotations: true`, one extra request per library per sync (60 s
    probe, auto-update libraries).
  - Before this, positions came only from:
    - shelf refresh;
    - opening Book Detail;
    - after a reader closes;
    - after a download.
- **Newer position from another device on shelf open (27561e53).** Restores the
  lost 2021 prompt without delaying opening. "Newer" means a later epoch,
  another device, and somewhere else (another `lastReadPage`, or ≥ 1% of
  progress away). Each position is offered once.
  - **Known locally:** `RecentShelfViewModel.tapBook` asks Go to It / Continue
    Here before opening (`RecentShelfAlert.newerPosition`).
  - **Otherwise:** the book opens at once. `ReadingSessionManager` then fetches
    the book's positions in the background (`.shelf` and `.newerPosition`
    opens, non-local servers) and broadcasts `newerPositionEvents()`.
    `MainViewModel.offerNewerPosition` alerts only while that reader is active
    and shown.
  - **Go to It** opens with `.newerPosition`: in the position's own reader if
    its format is cached, else the current one.
- **History of the old prompts.**
  - 2021-05..08: Book Detail's "picked a different reading position" confirm,
    removed in 17dc1fb6.
  - 2021-06..2022-04: MainView's confirm on close after jumping ahead > 10% or
    going backwards; disabled in 9ebc7283, deleted in bba8362a.
  - MainView still handles their dead `ForwardProgress`/`BackwardProgress`
    alert ids.
- **Verified:**
  - CI green on `f4f7a73f`.
  - Locally: 869 unit tests passed, 1 skipped, before the sync revert. The
    library and session tests pass after it.
  - Recent journey on the iPhone 17.
  - A Debug build installed and launched on the iPad Pro 10.5 (iOS 17.7).
- **Not verified:**
  - The user's iPad check of ▶ and the prompts was still in progress at merge.
  - The prompts in the running app: the mock library has only this device's
    positions.
  - Book Detail's cover read doesn't prompt.
  - `CalibreServerService.getLastReadPosition` and the DSReader Helper
    `readingPositionColumn*` settings are unused.

## Book Detail and Reading History Presentation (2026-10-12, merged)

**Merged to `main`** in drearycold/YetAnotherEBookReader#105 (merge commit
`3668f1b1`, 2026-10-13). The branch
`claude/bookdetailview-reading-history-refactor-1b8eb1` is deleted, remote and
local.
- **Verification at merge:**
  - CI green on `a22ed825` (iOS unit tests, Mac Catalyst build).
  - Locally: 856 unit tests passed, 1 skipped (the opt-in benchmark).
  - The Recent, Browse and main-tabs UI journeys pass on the iPhone 17 (iOS
    26.5) and the iPhone 7 (iOS 15.5).
- **Not covered:**
  - Discover's pushed Book Detail has no UI test: the mock library's Discover is
    empty.
  - Only YabrEPUB was opened end to end from a saved position. The other
    engines are covered by
    `testListViewModelContinueReadingOpensEveryEngineWithItsFormat`.
- **CI flake fixed on the way:**
  `ActivityListViewModelTests.testInitializationUsesRepositoryAndReceivesUpdates`
  runs first, while the fresh test host's startup can hold the main actor for
  more than 10 s. It now awaits `MainActor.run {}` before starting its 10 s
  deadline.

What changed:
- **The bug.** Continue Reading from Reading History opened the reader behind it.
  - The reader workspace is an in-tree overlay in `MainView` (`ZStack`, zIndex 10).
  - Book Detail (Recent and Discover) and Reading History were `.sheet`s, which
    are UIKit modals above the overlay.
- **The rule now:** a screen that can open a reader is pushed, never a sheet.
  Opening a reader also publishes `publishDismissAll`, which sheets and
  popovers subscribed to `dismissAllEvents()` close on.
  AGENTS.md "Book Detail" lists the hidden `NavigationLink(isActive:)` per
  screen.
- **Reading History redesign.** One inset-grouped List:
  - a compact 7-day chart;
  - a section per device, whose rows are sibling buttons (details, and ▶ to
    continue reading);
  - Local Sessions;
  - a DEBUG `DisclosureGroup`.
  - It is built from value rows made by `ReadingPositionHistoryViewModel`.
- **Shared opener.** `ReadingPositionListViewModel.continueReading(...)` returns
  an `AlertItem` or opens the reader. An unsupported reader now alerts instead
  of opening an empty workspace.
- **Closing a format preview** restores the session's reader info, as 29f311e5
  intended. It no longer opens the reader.
- **Deployment target.** iOS 15.6 → 15.5 (the user's call), so the iOS 15.5
  iPhone 7 can run tests.
  - On iOS 15 only the first `.confirmationAction` toolbar item showed, which
    hid Book Detail's history clock. Star and clock are now one
    `ToolbarItemGroup(.navigationBarTrailing)`.
- **Known risks:**
  - Pushed screens in Recent and Discover get the wood nav bar
    (`yabrAppChrome`). iOS 15 has no per-screen override.
  - History reloads while shown (`observeChanges`): on reader-info and
    presentation changes and on calibre updates, since a reader above it never
    makes it reappear.
  - **UI journey timing on iOS 15.** A FolioReader opened right after an earlier
    session restores the saved position a few seconds after its content
    appears, and an early swipe is undone. By hand, paging works.
    `testJourneyRecentDetailsAndFolioReader` therefore runs its paging check on
    a freshly opened book, before the new reader-from-detail and history
    activities.

## Current Branch Notes

- Reading regions (#97 spreads + columns, #19 column detection). Options
  `spreadMode` (Off/Auto/On) and `columnsMode` (Off/Auto), per book, default Off.
  - **Storage.** Optional Realm columns (schema 143): a nil row reads Off. A
    non-optional enum column reads "" on old rows and crashes RealmSwift's
    enum decode in every reader.
  - **Detection** (`PDFMarginCropController`).
    - `PageVisibleContentValue.regions` holds the regions in reading order,
      crop-relative and top-down like `bounds`; empty means the page reads
      whole. The region modes are part of `PageVisibleContentKey`
      (`init(pageNumber:options:)`).
    - **Spreads:** split at the crop box centre. Each half goes through
      `detectContentEdges` on a `PageRaster.cropped` sub-raster, so the spine
      shadow is the half's inner edge artifact. Auto needs a landscape page
      plus `hasSpreadSpine`: a blank or dark strip ≥ 2% of the width, the full
      height of the central sixth (a word space in a slide title is narrower).
      With one blank half, the page reads whole, fitted to the other half.
    - **Columns:** `PDFColumnDetector` runs on a `PDFInkMap` of the content
      box (or of each spread half). It classifies windows of about 4 lines,
      merges them into bands, and moves boundaries into the blank gap between
      blocks. It needs ≥ 40% of the content in columns.
      - **Text rule:** a split band stays split only if each column reads like
        running text: ≥ 4 lines of text height (≤ 4% of the content height)
        inked across ≥ half the column with no gap over an eighth of it,
        covering ≥ 30% of the column's inked height. Tables (label ... number)
        and figure grids read whole; a column that also holds a figure passes.
      - **Vertical text (TtB_RtL):** tiers (段). The ink map is turned a
        quarter (`turnedForVerticalText`), detected as columns, and turned
        back: read from the right, band by band, top tier first.
  - **Reading** (`YabrPDFViewController+ReadingFlow`, `PDFReadingFlow.swift`).
    - `PDFPageReadingPlan` holds every screen of every region
      (`PDFPageViewportFitter.screens`: equal steps, ≥ 10% overlap, last
      screen at the far margin; one screen if the content ends on screen by
      using the far margin), in display space. **A page read whole is one
      region** (its content box): in Page mode any page longer than the view
      at its fit steps a screen at a time. `readingPlan` is nil only for a
      page shown in one step (and in Scroll mode), which keeps the old
      fit/restore path.
    - The current step is derived from the view itself (top-left page point
      plus scale), not stored, so drags, zooms and restores need no
      bookkeeping.
    - **`turnPage`:** steps within the page first (`stepWithinPage`: apply the
      viewport plus the jump mask). Otherwise it sets `readingFlow`'s pending
      `.first`/`.last` before PDFKit or `takeOver` changes page;
      `handlePageChange` consumes it. Prev onto a long page lands on its last
      screen, not its saved position.
    - Buffers are prepared at the same arrival targets (next `.first`,
      previous `.last`), so `PDFReaderSurface` stays page-keyed.
    - Rotation and option changes set a pending `.region`
      (`readingRegionOnScreen`); it resolves to that region's step nearest the
      saved point (`stepIndex(nearestUpperLeft:…region:)`).
    - **Jumps** go through `jump(to:)` (destination, selection, highlight
      rect, bookmark). Targets: `.destination(rect)` lands on the last step of
      the region holding it that shows it; `.lowerLeft(point)` (bookmarks save
      `currentDestination`, the visible lower-left) the step with that corner.
      In single-page mode the page changes with `go(to: page)`: PDFKit's jump
      to a point or selection scrolls on sideways after `handlePageChange`.
      On the page on screen the step is applied directly under the mask.
    - **Page indicator:** `12 / 300 · 3/7` (turns) on a page with a plan;
      refreshed on page change, step, and when the bars come back.
    - **Step masks:** the next and previous step's masks are drawn ahead on a
      background queue (`prepareJumpMasks`, layouts from
      `PDFPageViewportFit.pageToView`), matched by page, size and layout and
      shifted by PDFKit's few-point landing offset. Dropped on theme,
      highlight, buffer release and memory warnings. Measured on a heavy scan:
      a step takes 1–4 ms with a prepared mask, 36–56 ms drawing it. A step's
      mask holds past 400 ms (≤ 1 s) while its newly shown tiles draw; a drag
      fades it.
  - **Still deferred:**
    - unmasked same-page steps (buffer takeover: viewport-keyed buffers plus
      per-view tile attribution);
    - two-axis stepping for over-wide regions;
    - per-page overrides; regions in Scroll mode.
- Margin-crop detection fixes (#94, #96), `PDFMarginCropController`:
  - **Ink by luminance** (Rec. 601 Y < 200): coloured text counts. The thumbnail
    is B G R A in memory; `PixelChannelOffsets` reads the real channel order.
  - **The reader's highlights are excluded.** Detection runs on a `PDFPage.copy()`
    without annotations carrying `highlightId`. Every highlight colour is ink by
    luminance, and a highlight on the first lines moved the top edge by ~37 pt
    (green highlights already did before). File annotations still count.
  - **Scans cross the whole page** (were stopped at mid-page). Text in one half,
    such as a chapter's last lines or a late opening, is found from the far edge.
  - **Side scans are scaled by the detected text height**, not by white lines in
    the outer quarters. On short pages the old scaling cut ~13 pt off line starts.
  - Folios were already ignored on full pages (too sparse to anchor, too far to
    pull in). #96's chapter-end symptom was the mid-page scan limit.
  - **Ragged edges (#93):** after the dense side edge, `extendBorderOverSparseInk`
    walks outward over any ink within the detected text rows, across gaps up to
    `max(4, lines/100)` px (about a word space). A few long lines, a long word or
    a trailing dash are kept. A marginal note further out, and running heads or
    folios outside the rows, are not. Both side edges are covered, so ragged-left
    text works too.
    - #93's scale jumps (Width mode) and left-margin wiggle (Page/Height mode
      only) were left alone by choice. Width mode already pins the left margin.
  - **Lines set off by extra space (#92):** `extendBorderAcrossLineGaps` still
    walks across gaps up to ~1.5x the body's line gap (`maxGap`, ~7 px for 11/15
    text). Across a wider gap, up to 4x the line pitch, it hops to the ink beyond
    only when that ink is:
    - line-like: at least half the body's first ink run, and 3 px;
    - outside the outer tenth of the page, where running heads and folios sit.
    - Hops repeat: paragraph tail → heading → body.
    - The gap alone can't tell a heading from a running head. In
      `BookPageGenerator` the head sits ~29 pt above the body; the probe's
      heading-to-body gap was ~32 pt.
    - The same hop keeps a one-line footnote below the body (#96's footnote case).
      It was cut off before.
  - **Scan artifacts (#95):** `PageRaster.edgeArtifactWidth` finds a scanner
    border or binding shadow on each edge:
    - a run of lines with at least half their pixels inked;
    - starting at the edge, allowing a thin light strip first;
    - ending within the outer tenth. A dark run that goes on is a full-bleed
      picture or tinted page, so it gives 0.
    - Each pass starts after the artifact on its own edge (`skip`). It also
      leaves out those on the other edges from its lines (`pixels`).
    - Before this, a gutter shadow inked every row. The top pass then saw no
      line gaps and stopped extending, which dropped paragraph tails.
    - `PageRaster` bundles the thumbnail bytes, size, row stride and channel
      offsets that were passed to every scan as separate parameters.
  - Scanned-page noise (specks) is still only limited by the walks' gap limits
    and the hop's minimum line height.
- Margin detection performance (2026-10-04), `PDFMarginCropController`:
  - **Pipeline.** `thumbnail(of:)` renders the media box once, without the
    reader's highlights. `analyze(_:key:)` reads it through
    `PageRaster.reading`, which uses the CGImage's own size and row stride
    and keeps its pixel data alive while read. Then come the edge passes,
    spread halves and columns.
  - **Removed:**
    - the crop-box render, which only fed a print;
    - the debug overlay (`thumbImage`), drawn at screen scale: 17 MB per
      Letter page at 3x, kept for up to 9 pages. Its viewer,
      `thumbController`, was never shown.
  - **Page number.** It now always opens `YabrPDFNavigationPageVC`
    (`presentNavigation`, shared with the toolbar's list button). It used to
    need a cached detection, so it did nothing on a book opened in Scroll mode.
  - **Reading lines.** `PageRaster.density` and `inkedPixels` walk a line
    through the bitmap in exact integers: darkness 255000 − (299r + 587g +
    114b) per ink pixel. The 14 colours exactly on the threshold, which the
    old floating-point sum rounded to ink, stay ink.
    - `PDFInkMap` keeps a `PDFInkTable` of ink counts for its own area. The
      map turned for vertical text is a view of it.
    - Whole-page summed-area tables were tried and dropped: building them
      (1–2.6 ms at -O) cost more than a text page's passes.
  - **Options changes.** The page on screen is re-detected from its render:
    `recentRenders` keeps three (the page and its neighbours, since a turn onto
    a buffered page can detect it on the main thread).
    It is main-thread only, and is dropped on `clearCache` and on memory
    warnings.
  - **Same results.** An A/B run against the old detector over every page the
    suite and the benchmark detect (575) found no difference.
    `PDFPageRasterTests` pins lines and ink maps to per-pixel reading.
  - **Benchmark.** `PDFMarginDetectionBenchmarkTests` is opt-in. Run it with
    `TEST_RUNNER_YABR_BENCHMARK=1 xcodebuild test …
    -only-testing:YetAnotherEBookReaderTests/PDFMarginDetectionBenchmarkTests`.
    - For optimized numbers, add `SWIFT_OPTIMIZATION_LEVEL=-O` and use its own
      derived data (`/tmp/YabrDerivedDataO`).
    - Points of Interest intervals (`PDFMarginDetection`, `PDFMarginRender`,
      `PDFMarginEdges`, `PDFMarginRegions`) profile it on a device.
  - **Numbers.** Median ms per page, iOS 26.5 simulator on the Mac, -O,
    before → after. The re-detection under other options is one slider step.

    | Page | Detection | Under other options |
    |---|---|---|
    | text | 23.2 → 3.0 | 23.2 → 0.39 |
    | blank | 23.4 → 2.4 | 23.4 → 2.0 |
    | paper, columns | 30.0 → 4.5 | 30.0 → 1.2 |
    | vertical tiers | 27.6 → 2.8 | 27.6 → 1.0 |
    | spread | 19.6 → 4.6 | 19.6 → 1.7 |
    | 300 dpi scan | 53.6 → 19.3 (18.7 render) | 53.6 → 0.45 |

    - Debug analysis is 1.2–2× faster.
    - `YabrPDFMarginCropTests` went from 175.6 s to 162.6 s; the unit suite
      from 214 s to 198 s.
  - **Not done:**
    - Our own rendering: drawing into our own context was within 10% of
      `PDFPage.thumbnail`.
    - 8-bit gray: CoreGraphics' gray isn't Rec. 601 on encoded values.
    - A smaller raster.
  - **Buffers wait for detection.** `refreshPageBuffers` lays out the
    neighbours only once both are detected under the current options. Before,
    a refresh after a cover ended could detect a neighbour on the main thread
    while the analysis queue was still detecting it, a render on the main
    thread (19 ms on the benchmark's scan). The queue's completion refreshes
    them instead (`testBufferRefreshLeavesUndetectedNeighboursToTheQueue`).
- Rotated pages (`page.rotation` ≠ 0) are detected and fitted as displayed:
  - **`PDFPageDisplaySpace`** (in `PDFPageViewportFitter.swift`) maps a page box
    to display space and back. PDFKit turns pages clockwise; display space has a
    bottom-left origin with y up, like page space.
  - **Detection.** `PDFPage.thumbnail` draws the page turned and aspect-fits it
    into the requested size. Asking for the unturned media-box size gave a
    shrunken raster (612×472 for a 90° Letter page) read at full scale.
    Detection now asks for the turned size, runs the passes in display space
    (so the top, line gaps and ragged edges are the ones the reader sees), and
    maps the rect back. `visibleBounds` still returns crop-relative,
    top-down page space.
  - **Fit.** `singlePageViewport` runs the fitter in display space. That
    includes the saved-axis keep: a NaN axis stays NaN through the turn. Only
    `pageAnchor` is mapped back; `applyViewport` converts through PDFKit.
  - **Saved position.** `getPagePoint` converts the view's top-left corner as a
    point. Taking `(minX, maxY)` of the visible rect in page space is wrong on a
    turned page.
  - `testRotatedPageFitShowsContent` no longer expects a failure. The remaining
    expected failures, `testProbeGoTo…`, record PDFKit's own `go(to:)`
    behaviour.
- Auto-hiding bars (FolioReader style):
  - **Behaviour.** A tap-zone page turn (not the toolbar arrows) and a drag of the page view on
    screen hide the nav bar and toolbar. The drag is detected by a target on
    PDFKit's scroll-view pan, added in `YabrPDFView.layoutSubviews`.
    A plain page tap toggles them (`surface.onPageTap` → `requestBarToggle`):
    - shown bars hide at once;
    - hidden bars show after `barRevealDelay` (0.3 s). The reveal is cancelled
      when a selection appears (a double tap selects a word).
    - `handleTap` returns whether the tap was used: a menu dismissed, a
      selection cleared, or a link followed.
  - **Layout.** The page is fitted to `pageLayoutInsets`, the navigation
    controller's own safe area without its bars, so the bars float over it.
    This supersedes "the top margin starts below the nav bar" below.
  - **No movement.** `setReaderBarsHidden` moves the bars' share of the safe
    area into `additionalSafeAreaInsets` while they are hidden. The page views'
    safe area, PDFKit's scroll insets and the placement don't change.
  - **Verified.** A recording shows the area between the bars unchanged at
    codec-noise level across toggles.
  - **PDF Options** (`presentOptions`) hides the bars while it is open and
    restores their previous state on dismissal (`DismissAwareHostingController`).
    - It is a popover anchored at the top right of the view with no arrow,
      because the Options button hides with the bar.
    - On compact width it is the popover's adaptive sheet: medium/large detents,
      undimmed at medium, so the page shows above it.
    - Page taps don't toggle the bars while it is open.
    - No `fixedSize()`: it clipped the options in the sheet.
- Viewport fix landed (uncommitted): `PDFPageViewportFitter` (pure, in
  `Views/PDFView/Managers/`) computes scale + per-axis page/view anchors inside
  the readable rect (`pdfView.bounds` minus safe area, so the top margin starts
  below the nav bar; text is top-aligned even when PDFKit would center a page
  shorter than the view). `YabrPDFView.applyViewport` drives the internal
  `UIScrollView` `contentOffset`, extending `contentInset` when the anchor is
  outside PDFKit's scrollable range. Fit and history-restore both use it; the
  bottom-right jump, `go(to:)` compensation passes, and DEBUG page annotations
  are gone. `marginOffset` moved from detection into the fitter.
- Tests: `YabrPDFMarginCropTests` (window-hosted, synthetic + generated
  book-like PDFs, real next/prev buttons) and `PDFPageViewportFitterTests`.
  Only the two PDFKit probe tests still use `XCTExpectFailure` (documenting
  `go(to:)` quirks the fix no longer relies on).
- Detection fix (`PDFMarginCropController.blankBorderWidth`): scans up to half
  the page (was a quarter; `whiteLines` keeps its quarter-page window so side
  sensitivity is unchanged), and on the line axis (top/bottom for `LtR_TtB`,
  right/left for `TtB_RtL`) walks outward over ink within ~1.5x the first
  inter-line gap, keeping short first lines and ascenders but not running
  heads. Vertical-text behavior is only covered by a solid-block test.
- Theme (uncommitted): iOS ignores `CALayer.compositingFilter` (verified with
  real `simctl io screenshot` captures; blend layers render opaque), so blend
  overlays are not an option. `PDFThemePalette` drives it: sepia/forest use a
  plain alpha overlay (`YabrPDFView.themeOverlayView`) solved so white maps
  exactly to the theme colour (black -> ~(34,23,0) / (0,27,7)); dark stays in
  `PDFPageWithBackground.draw`, now per-document via `PDFPageRenderTheme` on the
  document delegate (the global `static fillColor` is gone). `blankView` was
  replaced by `YabrPDFView.jumpMaskView`: an opaque snapshot of the target page at
  its final viewport, shown only for jumps (`markJumpTarget` ->
  `pendingJumpMaskPage`, consumed in single-page `handlePageChange`), never for
  next/prev. View order: document < jump mask < theme overlay < tap labels.
  Toggling dark re-attaches the document (`invalidateRenderedPages`): PDFKit's
  tile cache ignores both `annotationsChanged(on:)` and a scale round-trip, which
  left white tiles in dark and inverted tiles after leaving dark. Verify tile
  state only with real `simctl io screenshot` captures: `drawHierarchy`
  re-draws and does not show stale tiles.
- Flicker ("must never flicker"): verified with `xcrun simctl io booted
  recordVideo` + per-frame ffmpeg analysis (white/unthemed frames, A->B->A
  blips, text-ink drops); screenshots at 2-3 fps miss 1-2 frame flashes. Dark
  flashed white because PDFKit's per-page placeholder (`PDFPageLayer` >
  `backgroundLayer`: white + unthemed preview, drawn without our `draw`)
  shows before tiles render. Fixes: `YabrPDFView.invertsPagePlaceholders`
  (iOS 16 `PDFPageOverlayViewProvider` hook + KVO on the layer's
  contents/backgroundColor, iOS 15 best-effort via scroll KVO, untested);
  dark page turns freeze the current page first (`coverPageTurnIfNeeded`) since
  PDFKit's transition starts before `handlePageChange`; every dark page change
  is masked; a loading cover hides the first layout. Overriding
  `PDFPage.thumbnail` does not affect PDFKit's placeholder.
  `testDarkInvertsPDFKitPagePlaceholders` fails loudly if PDFKit renames layers.
- YabrPDF requires iOS 16 / Mac Catalyst 16 (uncommitted): `ReaderType.resolved()`
  maps YabrPDF to ReadiumPDF on older systems and `ReaderInfo.init` applies it,
  so every launch path falls back; YabrPDF types are `@available(iOS 16.0,
  macCatalyst 16.0, *)`. Menus are native (`Managers/PDFMenuManager.swift`,
  modelled on FolioReaderKit's `WebViewMenuManager`): selection actions are
  injected by `YabrPDFView.buildMenu(with:)`; tapping a highlight shows the
  app's own `UIEditMenuInteraction` (Copy / Select / Style ▸ / Delete). PDFKit
  has its own markup menu for highlight taps (Copy / Highlight / Remove / Add
  Note) that bypasses the app's persistence and does not go through
  `buildMenu`; `highlightMenuTapGestureRecognizer` only begins on a highlight
  and PDFKit's taps are required to wait for it. PDFView declares but does not
  implement `gestureRecognizer(_:shouldBeRequiredToFailBy:)` — never call
  super there. MenuItemKit / UIMenuController / `YabrPDFAnnotationView` are gone
  from YabrPDF (FolioReaderKit still uses MenuItemKit on iOS 15).
- PDFKit differs between iOS 18.5 and 26.5; run the PDF suites (and, for
  flicker, a `recordVideo` session) on both. iOS 18 leaves `PDFPageLayer`'s
  sublayers unnamed, so the placeholder is matched as `backgroundLayer` or the
  unnamed child at z = -900. iOS 18 centres a document smaller than the view by
  moving `PDFDocumentView` during layout, cancelling scroll offsets; the fit pads
  `pageBreakMargins` (single-page only, followed by `layoutDocumentView()`) so
  the document always covers the view, and continuous mode restores PDFKit's
  default margins via `restoreDefaultPageBreakMargins()`.
  The iOS 18 edit menu expands the highlight Style submenu inline and
  horizontally, without the swatch images or the ✓ on the current style that
  iOS 26 shows; both behave the same otherwise (verified by hand on 18.5/26.5).
- Highlight notes (FolioReader-style), new:
  - **Entry points.** "Note" appears in the selection menu; nothing is created
    unless a note is saved. The highlight menu has "Note" / "Edit Note", and the
    highlight list has swipe actions (Delete, Note / Edit Note).
  - **Editor.** `YabrPDFNoteEditorViewController`, a page sheet built with
    `themedNavigationController`.
  - **Storage.** `PDFAnnotationManager.setNote` saves through `didAddHighlight`
    (same id, upsert). A blank note clears it.
  - **On-page marker.** A small square in the top-right corner of the last
    line, built by `PDFHighlightAnnotations.noteMarker`. In light and sepia it's
    a highlight annotation in the same colour, so it reads as a darker patch
    with the text readable. It doesn't change margin detection, which counts a
    pixel as ink only when every channel is below 200.
  - **Rejected marker: custom `draw(with:in:)`.** PDFKit composites such
    annotations in a separate layer: on screen they are opaque, ignore the
    multiply blend, and skip the dark inversion.
  - **Export.** `annotatedExportDocument()` builds a fresh copy of the
    original file with standard annotations; the note goes in the first line
    annotation's `contents`, and there are no markers. The pages on screen are
    untouched.
- Dark-theme annotations: PDFView composites annotations over the page tile
  after `PDFPage.draw` (so over the already-inverted dark page), and multiplies
  markup annotations. In dark this left highlights as tinted text only, and
  Underline / strike-out invisible.
  - **Dark form.** `YabrPDFView.highlightAppearance` (`.dark`, set in
    `applyThemePalette`) rebuilds highlights: translucent filled squares, a
    2 pt bar for Underline (PDFKit doesn't fill a 1 pt square), and a bright
    square marker. Squares are composited normally.
  - **Snapshots.** Jump masks and dark page-turn covers use
    `PDFPageWithBackground.drawAsDisplayed`. It draws the page content
    (`drawPDFPage`), inverts in dark, then the annotations as PDFView does:
    highlights as an opaque multiply fill. `PDFPage.draw` draws them paler.
  - **Verified with `recordVideo`** on 26.5 and 18.5. Dark turns and toggles
    show no colour change. On light and sepia jumps the snapshot text renders
    slightly heavier than the tiles (it always did), and PDFKit draws on-screen
    highlights ~1-2 px taller than their bounds.
  - **List-delete fix.** Deleting from the highlight list now goes through
    the annotation manager. It used to bypass `activeHighlights`, and deleting
    the last row of a section used `deleteRows` after removing the section.
- #55 preload experiment (2026-09-29, iOS 26.5; temporary tile-draw log in
  `PDFPageWithBackground.draw`, since removed):
  - **When tiles render.** PDFKit renders a page's tiles only once the page
    is current, taking about 260-270 ms for a Width-fit page.
  - **Nothing renders ahead.** None of these made PDFKit draw the next page
    early: single-page mode, `usePageViewController(true)`, horizontal
    continuous mode (zero draws of the off-screen neighbour while idle), or a
    hidden second `PDFView` on the next page (tile caches are per view).
  - **What you see.** In `recordVideo`, parts of the new page stay a blurry
    low-res placeholder for ~140-190 ms after each light-mode turn.
  - **Only remaining option.** An app-side prerendered cover
    (`viewportSnapshot`-style), held until the page's tile draws stop. Its
    text must render like PDFKit's tiles, which are lighter than the
    current snapshots.
  - **Industry practice.** pdf.js, Nutrient (PSPDFKit), KOReader/MuPDF and
    AndroidPdfViewer all use their own renderers. They render neighbouring
    pages ahead in the direction of travel into a page-bitmap cache, give the
    visible page priority with cancellable prefetch, and tile only when zoomed.
  - **Chosen direction.** Option A: a hybrid PDFView plus prefetched cover.
    Snapshot fidelity is validated first.
  - **Fidelity check** (real `simctl io screenshot`, compared inside the page,
    iOS 26.5):
    - **Tile resolutions.** PDFKit renders tiles at two levels: exactly the
      screen resolution (`scaleFactor` x screen scale) and 100% zoom x screen
      scale (downscaled for display).
    - **Image covers never match exactly.** Every image cover differs on glyph
      edges: `viewportSnapshot` averages 8.5 per pixel, a page image at
      exact resolution 6.4, and one at 3 px/pt downscaled by Core Animation
      5.7. Ink totals match; no whole-pixel shift helps.
    - **A second PDFView matches.** A `YabrPDFView` on the same page with the
      same viewport (`applyViewport(restore(...))`), rendered behind and then
      brought to the front, has zero difference except under the tap-zone
      labels (alpha 0.01), which the cover sat above in the test.
    - **So the prefetch cover should be a second PDFView** placed below the tap
      labels and the theme overlay, as `jumpMaskView` is.
  - **Direction.** Triple buffer behind a `PDFReaderSurface` container that
    owns 1-3 `YabrPDFView`s and all per-view state.
    1. Pure refactor with one view.
    2. Buffers with a cover policy.
    3. Takeover policy.
  - **Gesture-priority experiment** (iOS 26.5 and 18.5, real taps in the
    harness).
    `YabrPDFView` was moved into a container, and its four app tap recognizers
    plus the app's `UIEditMenuInteraction` were moved onto the container. The
    delegate stays the view and uses `location(in: self)`. Results:
    - tapping a highlight shows the app's highlight menu, not PDFKit's markup
      menu;
    - long press selects text, and the system edit menu shows the app items;
    - corner single-tap and edge-strip double-tap turn pages.
    - **Caveats.** PDFView has its own `UIEditMenuInteraction` (text selection)
      that must stay on the PDFView. A view moved to a new parent at runtime
      needs `translatesAutoresizingMaskIntoConstraints = true`, or its
      constraints drop and it collapses. Tap zones are the bottom corners
      (single tap) and 50 pt edge strips (double tap).
    - **Harness quirk.** In a freshly started window-hosted test, the
      text-selection system menu appears only after a sheet has been presented
      once, with or without the container.
    - The same checks pass on iPhone 16 (iOS 18.5).
  - **Step 1 done.** `PDFReaderSurface` hosts the single `YabrPDFView`.
    `controller.pdfView` is read from the surface; nothing stores it, and the
    controller observes the surface's relayed notifications. The surface owns:
    - the theme overlay, jump mask and loading cover;
    - the tap zones and labels, and the app's four taps with their delegate
      rules;
    - the highlight edit-menu interaction;
    - the highlight model (`highlights`, sources, appearance,
      `highlightTapped`, inject/remove/export/hit-testing).

    `YabrPDFView` keeps what is per view: viewport, snapshot, placeholders,
    `buildMenu`, and taps off highlights (`handleTap`). `pdfViewAux` has its
    own surface.
  - **Found by hand in step 1.** PDFKit makes its taps (including the text
    interaction's double tap on `PDFDocumentView`) wait for recognizers
    attached to the PDFView, but not for ones on an ancestor. The surface
    declares that PDFKit's taps inside the page view wait for its page-turn and
    highlight-menu taps. Without this, a side-zone double tap also selected a
    word.
  - **Step 2 done: buffers with a cover policy.**
    - **Buffers.** `PDFReaderSurface` keeps two non-interactive `YabrPDFView`
      buffers behind the active view, showing its neighbours
      (`refreshPageBuffers`, after neighbour detection completes).
    - **Shared viewport.** `singlePageViewport(for:in:)` is shared by the page
      on screen and the buffers.
    - **Covering.** `handlePageChange` calls `coverWithBuffer(showing:)`, which
      brings the matching buffer above the active view, below the overlays.
      - It requires the same scale, margins and content size, and a top left
        within 24 px.
      - It then copies the active view's exact inset and offset
        (`alignScrollPosition`). The same fit can land 1-4 px apart depending
        on how each view got there, most on iOS 18.
    - **Handover.** The cover ends once the active view has drawn every tile it
      shows (timeout 1 s). PDFKit first draws a new page at 100% zoom (the old
      blurry/heavy intermediate), then at `scaleFactor x screen scale`.
      (Superseded detail: it used to wait for any draw plus 60 ms of quiet; see
      the review fixes below.)
    - **Dark.** Buffered dark turns skip the freeze and page-change snapshot
      masks: a snapshot's glyphs render heavier than tiles, visible as the mask
      faded.
    - **Verified by recording** (iOS 26.5): light and dark turns each change
      once, from the old page to the final new page. There are no placeholder,
      intermediate or bright frames, and the handover is at codec-noise level.
  - **Test-environment deadlock.** PDFKit analyses visible pages with Vision
    (`PDFPageAnalyzerV2` on the document's `formFillingQueue`). About 67 test
    documents with pending analyses exhaust GCD's worker pool, so the global
    utility queue never runs again in that process. Two fixes:
    - Margin detection uses its own serial queue; private queues still get
      threads.
    - `buildTocList` runs on the main thread (it also raced on `tocList`).

    In the app only one document is open, and analysis is serial per document.
    - **Root fix (2026-10-09).** `YabrPDFMarginCropTests` turns the analysis
      off for the class: `PDFKitDocumentAnalysis` swaps the IMP of PDFView's
      private `isDocumentAnalysisEnabled` getter (checked first by
      `-[PDFView visiblePagesChanged:]`) and restores it in class `tearDown`.
      No Vision or `formFillingQueue` threads remain, and the full unit target
      (833 tests) runs in about 200 s instead of hanging.
    - **What the hang looked like.** Each waiting Vision request parks a GCD
      constrained-pool worker (`kern.wq_max_constrained_threads` = 64). Once
      64 are parked, Vision deadlocks for good. UIKit then hangs the main
      thread in `_UIBoundingPathBitmap` (`dispatch_group_wait`) the first time
      it computes a bounding path for a new window size. The
      `UISheetPresentationController` frames in that stack are not a leaked
      sheet: on iOS 26, `_UIRootPresentationController` (each window's root VC)
      subclasses `UISheetPresentationController`.
  - **Step 3 done: takeover.** `turnPage(forward:)` (the prev/next buttons and
    tap zones) first calls `surface.takeOver(showing:viewport:)`.
    - **What it does.** A buffer holding the target page, laid out like the
      active view and with every tile it shows drawn since it got the page,
      becomes the active view. The old active view becomes a buffer that already shows the
      new neighbour.
    - **What moves.** Notification relay, interactivity and accessibility, the
      delegate, selection (cleared) and the highlight menu (dismissed).
    - **Page change.** The surface posts the page change itself;
      `handlePageChange` consumes it (`consumeTakeover`), with no cover and no
      mask.
    - **Fallback.** Otherwise the PDFKit turn plus cover from step 2. Under
      dark, only a rendered buffer replaces the masks: an unrendered one shows
      PDFKit's white placeholder, which a recording caught on fast turns.
    - **Recordings** (iOS 26.5): normal light and dark turns change once. Turns
      faster than a buffer can render (~250 ms) fall back as before: light
      shows the placeholder for a few frames, dark shows the snapshot masks.
    - **Test trap.** A scale near 1.0 counts as rendered, because PDFKit's
      first pass renders every page at 100% zoom.
  - **Review fixes (2026-09-30)**, from a peer review of `main...79ed2e96`:
    - **Tile-level draw log.** All page views' tiles render on one queue
      (`PDFKit.PDFTilePool.workQueue`), so a draw cannot be tied to a view.
      Tiles can be identified, though (experiment, identical on iOS 18.5 and
      26.5):
      - Tiles are 1024 px squares with a 1 px border, anchored at the display
        box origin; tile (c, r) draws with ctm translation (1 - 1024c, 1 - 1024r).
      - PDFKit draws the visible tiles plus a ring of margin tiles.
      - `PDFPageTile` and `PDFPageRenderTheme.tileDrawCounts` implement this.
    - **What uses it.** "Rendered" means every tile the view shows has drawn
      since the buffer got its page or a new scale. It used to mean a single
      draw, so a half-rendered buffer could take over.
    - **Cover handover.** A covering buffer that had not finished counts as
      owing its missing tiles (`coverOwedTiles`); the active view has drawn
      those only on their second draw.
    - **Fallback.** Draws off the grid (another OS or Catalyst tile size) fall
      back to "any draw plus 60 ms quiet". `testRenderedPageDrawsArePDFKitTiles`
      guards the grid.
    - **Takeover also** posts a scale change (so `lastScale` follows) and skips
      buffers laid out differently (direction, RTL, box) until they are
      refreshed.
    - **Snapshots.** `drawAsDisplayed` now draws PDFKit annotations in box space
      (`PDFAnnotation.draw(with:in:)` applies the box transform itself). Before,
      underlines and dark squares were offset on pages with a non-zero crop
      origin. `invertedImage` shares `PDFPageWithBackground.invert`.
    - **Dark freeze.** It copies the screen (`snapshotView(afterScreenUpdates:
      false)`), or keeps a mask that is still showing, instead of drawing the
      page again.
    - **Scale changes.** `lastScale` changes from `handleScaleChange`
      (`isRecordingScale`) only persist; they no longer restyle the chrome.
    - **Continuous mode** drops the viewport's extra inset.
    - **Progress.** It is reported for restored positions too. The transient
      first page during `invalidateRenderedPages` is ignored
      (`isReattachingDocument`); the old early return had hidden it.
    - **Status bar.** It is light only in the reader workspace
      (`presentationID != nil`); the book preview keeps UIKit's default.
    - **Not changed.** The placeholder detection's dependence on private layer
      names is already guarded by `testDarkInvertsPDFKitPagePlaceholders`.
  - **Page dragged off screen (2026-09-30, iPad, TtB_RtL + Height).** Two causes:
    - **Padding counted twice.** PDFKit applies `pageBreakMargins` twice per
      side, so `padPageBreakMargins` (one view-excess per side, meant to keep
      the page between flush left and flush right) let a narrower page be
      dragged almost entirely off either edge.
    - **Fix: `confineScrollRange`**, which runs after every `applyViewport`,
      sets the scroll range (via `viewportExtraInset`, which may be negative).
      Along an axis where the page fits the view it stays inside; otherwise it
      keeps covering the view; the fitted placement stays reachable. A pinch
      zoom keeps the old range until the next viewport.
    - **Stale saved axis.** Switching TtB_RtL from Width to Height kept the
      saved top-left x, which put the page at the left of the view. A saved
      axis is now kept only while the content overflows the view along it.
    - **RtL centering.** TtB_RtL content that fits the width (e.g. Page fit on
      an iPad in portrait) is now centered horizontally, mirroring LtR. Content
      wider than the view still starts at the right margin.
    - **Test-deadlock recurrence.** Four extra window harnesses (3 pages each)
      tipped the PDFKit Vision / GCD-pool deadlock (main thread stuck in a
      `dispatch_group_wait` inside UIKit bounding-path layout). The analysis
      is now off in the tests (see the root fix above), so harness count no
      longer matters.
  - **Consent prompts in tests.** Tests skip the ATT and ad-consent (UMP)
    prompts (`UITestingConfiguration.skipsConsentPrompts`: the UI-test launch
    argument or the unit-test host). Otherwise the UMP form covered the UI
    tests and window-hosted sessions.
  - **Hand-check tips.** After `xcodebuild` reboots a simulator, `attach` the
    Simulator tool before the first tap, or the running test app is killed.
    Run the next session without `simctl shutdown` to keep the connection.
- In tests, `ReadingSessionManagerTests.tearDown` sets `AppContainer.shared =
  nil`; window-hosted harnesses must recreate one before adding a window or the
  host's SwiftUI `appContainer` environment default asserts.
- Persisted `pageOffsetX/Y` keep the visible upper-left semantics
  (`getPagePoint` now measures `convert(bounds, to: page)`).
  `rememberInPagePosition` is still never read by navigation code.
- `ReadingPositionViewModelTests.testDetailViewModelReadSelectedFormatOpensReaderPresentation`
  failed on `main` since it was added: `CalibreBook` is a struct, so the cached
  EPUB set on `mockBook` never reached `listViewModel.book` and
  `readSelectedFormat()` raised "Selected Format Not Cached". Fixed with the same
  setup as `8437dcaf` (`codex/dsreader-advanced-qa-integration`), plus an
  `alertItem` assertion that names the alert if the guard trips again.
- PR #88 (`codex/folio-reader-integration`) has been merged. Reader workspace,
  FolioReader integration, reader tab hot-mounting, and persistent active reader
  restore are archived in [Reader Modernization](history/reader-modernization.md).
- The manual sync metadata refresh cleanup from the same merged branch is
  archived in [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md).
- Keep this file as a short handoff entrypoint. Add only current, unresolved, or
  high-risk context here; move completed project records into the matching
  history file before merge.
- If a task changes architecture, validation status, known risks, or handoff
  expectations, update this file or the relevant history file before finishing.

## History Index

- [Reader Modernization](history/reader-modernization.md): Readium,
  FolioReader, PDF reader, reading position, highlights, preferences, Book
  Detail reader work, and reader workspace/window modernization.
- [AppContainer And Concurrency Modernization](history/app-container-concurrency-modernization.md):
  AppContainer demotion, manager async streams, Combine removal, and concurrency
  hardening.
- [Shelf Modernization](history/shelf-modernization.md): Recent/Discover shelf
  UI, `YabrShelfDataModel`, shelf bootstrap, and shelf Swift Concurrency
  migration.
- [Realm Boundary Convergence](history/realm-boundary-convergence.md): Realm
  boundary shrinkage, repository ownership, mapper extraction, and persistence
  cleanup.
- [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md):
  Calibre networking, unified search/category, cache behavior, downloads, and
  network tests.
- [ModelData Elimination](history/modeldata-elimination.md): ModelData
  reduction, AppContainer introduction, protocol migration, and final deletion.
- [Legacy Completed Tasks And Milestones](history/legacy-completed-milestones.md):
  Older completed checklists and cross-cutting historical context.
- [UI Test Modernization](history/ui-test-modernization.md): offline mock
  fixtures, Browse/search/category coverage, FolioReader flow, journey
  consolidation, and performance-plan results.

## Active Constraints

- Preserve user changes; do not revert unrelated dirty work.
- Do not introduce CocoaPods, Carthage, or workspace-level dependency changes.
  The project uses Swift Package Manager.
- Prefer repositories/services/managers over direct Realm or network work in
  SwiftUI views.
- Before any `xcodebuild test`, run:

```bash
xcrun simctl shutdown all
```

- Standard iOS Simulator build:

```bash
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

## Current UI Test Note (2026-07-12)

- The offline UI suite currently contains five journeys and 11 named
  activities; full history and verification are archived in
  [UI Test Modernization](history/ui-test-modernization.md).
- Stable two-clone scheduling remains unresolved on Xcode 26.5/CoreSimulator.
  Use the dedicated performance scheme/plan for experiments and do not treat
  the accepted 180-second deviation as a guaranteed performance baseline.

## CI (2026-10-09)

- `.github/workflows/ci.yml`: iOS unit tests (`YetAnotherEBookReaderTests`
  only) and a Mac Catalyst build on `macos-26`, Xcode pinned by
  `XCODE_VERSION`. See AGENTS.md "CI".
- 2026-10-10: no local packages any more; `.github/local-packages.txt`, its
  script and CI's checkout step are gone. Every package is remote and recorded
  in `Package.resolved` (AGENTS.md "Swift Packages").
  - FolioReaderKit stays an independent library, followed on its `master`
    branch (its default; there is no `main`). Its `styling-optimization` was
    merged into `master` in FolioReaderKit#9; #10 went to
    `styling-optimization` by mistake and was brought over in #11.
  - Building against an unpushed FolioReaderKit: a workspace outside the repo
    with the project and the local checkout; the local package overrides the
    remote one (checked: 69 FolioReaderKit sources compiled from the checkout).
- SwiftUICharts became a remote package at its 2.10.4 release, and
  `swift-toolkit` a remote package on the fork
  (`dsreader/readium-swift-toolkit`, branch
  `feature/additional-safe-area-insets`, 003be49 = 3.8.0 + one commit).
  - That commit's content-inset change is dead code for YAEBR: the EPUB
    controller's `navigatorContentInset` returns the insets in paged mode, and
    scroll mode sets `additionalSafeAreaInsets` to zero.
  - Its margin-swipe `hitTest` is upstream as readium/swift-toolkit#872
    (issue #112), in `develop` and 4.0.0-alpha.2 but not 3.11.0. Move to
    upstream 4.0 when it is released and drop the fork.
  - Changing the package reference re-resolved Readium's dependencies to newer
    versions; the old pins were restored in `Package.resolved` by hand.
- Locally with CI's commands from clean derived data (2026-10-09): the build
  for testing took 181 s and 835 unit tests passed in 200 s (1 skipped, the
  benchmark). The Catalyst build works again; the old "blocked by SPM product
  resolution" note is gone from AGENTS.md.
- CI's simulator is fresh. The first run failed 12 tests that passed locally:
  - 5 relied on a leftover `Local Library/Mock Book Title.epub` on the
    developer's simulator. `AppContainer(mock:)` installs that EPUB only for UI
    tests; unit tests that open the mock book call
    `TestFixtures.cacheMockBookEPUB(in:)`. Reproduce such failures locally by
    moving the test host's `Documents/<dir>` aside (and back afterwards).
  - 7 hit 1–3 s waits on the slower runner (`YabrPDFMarginCropTests` buffers;
    `ActivityListViewModelTests`, the first class, while the host starts).
    Use deadline waits with a generous bound (10 s) that end on the condition.
- Not in CI yet: the UI journeys, iOS 18 / iPad runs, DerivedData caching.

## FolioReader vertical writing stuck on "Finalizing" (2026-10-10)

- Symptom: 陈寅恪文集(全9册)(竖排) (`vertical-rl`, `page-progression-direction="rtl"`),
  paged mode, iPad Pro 10.5" iOS 17.5 in landscape: the page never left
  "Finalizing…" (the overlay now says "Loading…").
- Cause: the reader workspace toolbar measures 54.5 pt there, so
  `readerToolbarInset` gave the reader 751.5 pt. FolioReaderKit's vertical
  viewport is `height=device-height`; WebKit rounds the height to 752 px and
  scales the width (780 × 752/751.5 → 781 px), so it paginates 781 px pages on a
  780 pt web view. `updateStyleBackgroundPadding` sizes the body in screens until
  the page count matches and went round forever (34 → 35 → 34 …). Any web view
  at least as wide as it is tall with a fractional height does this (also on
  iOS 26.5 WebKit); portrait rounds back to the width.
- Fix: FolioReaderKit floors the web view frame to whole points and stops the
  padding search when it would repeat a step (drearycold/FolioReaderKit#10,
  into `styling-optimization`); YAEBR rounds `readerToolbarInset` up to whole
  points (`MainView.swift`), which alone avoids the 751.5 pt reader here.
- FolioReaderKit#10 is merged (`13358e8`), and on `master` through #11. A 3x screen or another Dynamic Type size gives
  other fractions, which only the library fix covers.
- Debugging recipe used: lldb on the running simulator app; with a stale build
  the Swift debug info doesn't match, so read state through ObjC expressions
  from `UIApplication.windows` (WKWebView frames, `evaluateJavaScript` writing
  results to `document.title`). `simctl launch --stdout=<path>` writes under the
  device's `data/` root (`/private/tmp/x` → `data/tmp/x`).

## YabrPDF reader leak (2026-10-10)

- Every closed YabrPDF reader leaked: the chrome's `UIAction`s (slider,
  prev/next, back, aux, Annotations, Share, history items) captured the
  controller strongly and live in its own view, so the controller, its
  `PDFReaderSurface`, buffers and `PDFDocument` were never released. Now
  `[weak self]` (`YabrPDFViewController+Chrome.swift`, `+Navigation.swift`).
- Found through CI: in the suite the leaked readers piled up and later
  `YabrPDFMarginCropTests` slowed until 10 s waits ran out (`waitForBuffers`
  saw no buffers). Running the class 3 times locally reproduced it (36 failures
  in the third pass); with the fix 516 tests passed and per-test times stay flat.
- `testClosedReaderIsReleased` checks the controller and document go away
  (the tap-zone preview's 3 s `asyncAfter` holds the surface that long).
- To check a release in a test, tear the window down inside an
  `autoreleasepool`: `rootViewController = nil` autoreleases the old root,
  and the test's own pool only drains after the test.
