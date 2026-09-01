# CoasterHunter

A theme park and roller coaster companion for iPhone and Apple Watch. Does what
LogRide does — the world's parks, coasters and credits, check-ins, trip reports —
and adds the differentiator: the watch measures the ride. Peak g, airtime,
inversions and roughness, captured on the wrist while the phone is in a locker.

Read `README.md` first for structure and commands. This file covers the
decisions behind the code, which are not obvious from reading it.

## Where the project is

| Part | State |
|---|---|
| `pipeline/` | Working, 19 tests. Builds a 7.1 MB SQLite seed database |
| `CoasterHunterCore` | Working, 61 tests / 159 assertions |
| SwiftUI app + watchOS | Written and typechecked, **never compiled for iOS** |
| Xcode project | Defined in `project.yml`, never generated |

The original development machine had no Xcode (macOS 13, insufficient disk), so
nothing has been built for iOS or run in a Simulator. Expect the first real
build to surface errors — that is anticipated, not a regression.

## Decisions that must not be quietly reversed

**OpenStreetMap is deliberately excluded from the seed database.** Its ODbL
share-alike attaches to *derivative databases*, so merging OSM data would risk
obliging us to publish our own database under ODbL. OSM is a runtime
map-display source only. Do not add it to `pipeline/`.

Wikidata is CC0, which is why it is the identity spine — everything built on top
of it stays ours. Wikipedia gives facts only (numbers, dates, manufacturers);
never reuse its prose or images.

**The name-match threshold in `pipeline/src/match.mjs` is 0.86 and lowering it
corrupts the database.** Valleyfair genuinely has both a "Wild Thing" and a
"Mild Thing". Six real rides were failing to match; the fix was name-variant
normalisation (`nameVariants` in `src/util/text.mjs`), not a looser bar. There
are tests pinning both behaviours.

**There is no monthly subscription, on purpose.** Park visits are seasonal, so a
monthly subscriber churns every October and must be reacquired every spring. The
£4.99 3-Day Park Pass serves the same "I won't commit" need with no churn.

**The 3-Day Pass activates on tap or first check-in, never at purchase.** People
buy it the night before a trip; starting the clock at purchase would burn a day
they paid for. It is a StoreKit *non-renewing subscription* because
auto-renewable products have a one-week minimum period. Apple does not track its
expiry — that clock lives in `EntitlementService` and is tested.

**Backdated and manual laps must never reach leaderboards.** See
`LapSource.eligibleForLeaderboards`. A lap logged from memory has no telemetry
and cannot compete with a measured one.

## The sensor thresholds are reasoned, not calibrated

Every constant in `MetricsCalculator.Thresholds` and `RideCaptureSession
.Configuration` was derived from physics and argument, **not from a single real
trace**. No ride has ever been recorded. Treat the numbers as a starting point:

- airtime below 0.5 g, sustained runs ≥ 0.4 s
- inverted beyond 120° of tilt, for ≥ 0.25 s
- roughness is RMS jerk band-passed 4–20 Hz, scaled by a guessed constant
- capture ends after 7 s at rest — raised from 4 s because several Intamin and
  B&M layouts hold on the mid-course brake for five seconds or more

**The highest-value next task is recording real laps on rides with published
figures and recalibrating against them.** Fixtures in `TraceFixtures.swift` are
constructed so expected values are arithmetic; keep them when real traces
arrive, do not replace them.

## Toolchain workarounds that should now be deleted

Two things exist only because Xcode was unavailable:

- `Packages/CoasterHunterCore/Tools/run-tests.sh` + `Tools/XCTestShim.swift` —
  a minimal XCTest stand-in so tests could run without Xcode. The test files
  are normal XCTest and guarded by `#if !SHIM_TESTS`.
- `CoasterHunter/Tools/typecheck-app.sh` — typechecks SwiftUI against the macOS
  SDK.

Once `swift test` and `xcodebuild` work, delete both and remove the
`#if !SHIM_TESTS` guards from the test files.

## Worth reconsidering on a newer Mac

The deployment target is **iOS 17 / watchOS 10**, chosen only because macOS 13
capped the toolchain at Xcode 15.2. On a machine running current Xcode this
could be raised to iOS 18+, which would bring `@Observable`, Swift 6 concurrency
checking and the current watchOS APIs. Ask before changing it — it is a product
decision about which devices to support, not just a build setting.

## Conventions

- All measurements stored metric. Sources mix feet, mph, inches and centimetres.
- Optional spec fields are genuinely optional — the free sources are incomplete.
  Show gaps honestly; never print a zero for a missing height.
- `AttractionKind.other` is a legitimate value, not a classification failure.
  Parks list game booths and character meets alongside rides.
- Logic that needs judgement goes in `CoasterHunterCore` so it can be tested.
  Views and CoreMotion bindings stay thin.
