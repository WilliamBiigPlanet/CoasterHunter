# CoasterHunter

A theme park and roller coaster companion for iPhone and Apple Watch.

Everything LogRide does — the world's parks, coasters and credits, check-ins,
trip reports, stats — plus the thing no logging app has: the watch measures the
ride. Peak g, airtime, inversions and roughness, captured on the wrist while the
phone sits in the locker.

```
setup.sh          First-run setup after cloning
pipeline/         Builds the seed database from free, openly-licensed sources
CoasterHunter/    The iOS and watchOS app
blueprint/        Product blueprint — pricing, feature set, design language
Design Style Reference/   Visual direction (local only — not in the repo)
```

## State of play

| Part | Status |
|---|---|
| Data pipeline | **Working and tested.** 19 tests, produces a 7.1 MB database |
| `CoasterHunterCore` | **Working and tested.** 61 tests, 159 assertions |
| SwiftUI app layer | **Written and typechecked**, not yet compiled for iOS |
| watchOS app | **Written and typechecked**, needs a device to validate |
| Xcode project | **Defined in `project.yml`**, not yet generated |

Xcode is not installed on the development machine, so nothing has been built for
iOS or run in the Simulator. The logic that could be verified without it has
been, deliberately — the sensor maths, ranking and entitlement rules all live in
a platform-agnostic package with real tests, and the SwiftUI layer typechecks
against the macOS SDK that Command Line Tools ships.

## Getting to a running app

After cloning, run the setup script. It checks your tooling, builds the seed
database and runs the tests:

```bash
./setup.sh
```

Then generate and open the Xcode project:

```bash
brew install xcodegen
cd CoasterHunter && xcodegen generate && open CoasterHunter.xcodeproj
```

Deployment target is iOS 17 / watchOS 10.

## Verification

Everything below runs today, without Xcode:

```bash
cd pipeline && npm test                              # 19 tests
cd pipeline && npm run build                         # rebuilds the database
cd CoasterHunter/Packages/CoasterHunterCore && ./Tools/run-tests.sh   # 61 tests
cd CoasterHunter && ./Tools/typecheck-app.sh         # SwiftUI layer
```

Once Xcode is installed, `swift test` runs the same test files natively and
`Tools/run-tests.sh` becomes redundant.

## The database

Built entirely from free sources — no licensing spend, and nothing that
constrains what the app can become.

| Source | Licence | Contribution |
|---|---|---|
| [ThemeParks.wiki](https://themeparks.wiki) | Free API, MIT client | 198 parks, full attraction lists, live waits |
| [Wikipedia](https://en.wikipedia.org) | CC BY-SA 4.0 | Coaster spec sheets — facts only, never prose |
| [Wikidata](https://www.wikidata.org) | CC0 | Cross-references, park metadata |
| [Queue-Times](https://queue-times.com) | Free, attribution | Live wait times |

Current coverage: **198 parks, 8,229 attractions** (96.7% with coordinates),
**527 coasters** with spec sheets — of which ~90% have height, length and speed
and 97.6% have a manufacturer. See `pipeline/out/coverage.md`.

**OpenStreetMap is deliberately excluded from the seed database.** Its ODbL
share-alike attaches to derivative databases, so merging it would risk making
CoasterHunter's own data open by obligation. OSM stays a runtime map-display
source only.

Wikidata is CC0, which is why it is the identity spine: everything built on top
of it stays ours.

## Pricing

| Product | StoreKit type | Price |
|---|---|---|
| 3-Day Park Pass | Non-renewing subscription | £4.99 |
| Pro — one year | Auto-renewable, 14-day trial | £19.99 |
| Pro — lifetime | Non-consumable | £54.99 |

There is no monthly plan. Park visits are seasonal, so a monthly subscriber
churns every October and has to be reacquired every spring; the pass serves the
same "I won't commit" need with no churn to manage.

The pass is a non-renewing subscription because auto-renewable products have a
one-week minimum period. Apple does not track its expiry, so that clock lives in
`EntitlementService` where it is tested. It activates on tap or on first park
check-in, never at purchase — people buy these the night before a trip.

## Still to do

- Wire the seed database into the app's data layer
- Supabase schema, migrations and sync
- Park detail, search, profile and logbook screens
- Record real traces on a real ride and recalibrate the metric thresholds
