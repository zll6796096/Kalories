# App Store Release Foundation Evidence

Date: 2026-08-11 (Asia/Tokyo)
Scope: local source, tests, metadata, packaged public pages, unsigned build, and committed screenshots only
Gate source revision: `986d0782d41c11e2574f1bebe1ca447105c3c543`
Branch: `codex/kalories-testflight-build1`

## Approved identity

- App: カロスキャン
- Apple app ID: `6799957568`
- Bundle ID: `com.ryuaistudio.kalories`
- Version/build: `1.0.0 (1)`
- Territory: Japan only (`JPN`)
- Price: Free
- In-app purchases: None
- Subscriptions: None
- Release: Automatic after approval (`AFTER_APPROVAL`)
- Audience: Users aged 18 or older; not in the Kids category
- Contact: `zll6796096@gmail.com`
- Copyright: `2026 RYU AI Studio`

## Distribution source settings

- Development team: `YMUG864233`
- Release signing style: Manual
- Release signing identity: `Apple Distribution`
- Release provisioning profile specifier: `Kalories App Store`
- Export-compliance declaration: `ITSAppUsesNonExemptEncryption = false` in both the source and the locally built Release app
- Signed archive, installed profile, signing certificate, and Apple portal validity: UNVERIFIED

The successful generic Release build disabled code signing. It proves compilation
and packaging only; it does not prove that the named distribution profile can
sign or upload the app.

## Adult-access contract

- Minimum age: 18
- Confirmation is required before the app flow is available.
- The persistent key is `kalories.adult-access.confirmed.v1`.
- Only a literal Boolean `true` grants access.
- The confirmation stores only that the user selected “18歳以上です”; no birth date, name, or identity document is collected.
- The confirmation is not added to analysis requests and is not sent to the Kalories backend, Google, or Firebase.
- Japan higher-age-rating target: `18+`.
- Japan iOS 26-or-later rating readback: UNVERIFIED (`null` in metadata).
- Japan earlier-OS rating readback: UNVERIFIED (`null` in metadata).

## Local gates

- Web tests: PASS — 23/23 tests across 3/3 test files.
- Python tests: PASS — 164/164 tests.
- TypeScript check, web build, Python bytecode compilation, runtime imports, and dependency compatibility: PASS.
- Docker image build: PASS — manifest `sha256:4cd459c71a3863c1971deb27095160d179097ba14fa5169d29e91288cc77cef1`.
- Generated iOS localizations: PASS — 6/6 generated files current.
- iOS unit tests: PASS — 136/136.
- iOS UI tests on iPhone 17 Pro, iOS 26.5: PASS — 4/4 runnable tests; 0 failures.
- Pro-Max-only screenshot UI test in the full iPhone 17 Pro run: SKIPPED — 1 test; the test requires the iPhone 17 Pro Max logical size `(440, 956)` and fail-closed on the `(402, 874)` destination.
- Xcode result summary: PASS — 140 passed, 1 skipped, 0 failed, 141 total.
- Unsigned generic iOS Release build: PASS.
- Local App Check release scan: PASS; external configuration: UNVERIFIED.
- Public privacy/support package: PASS — 8/8 focused tests.
- Japanese metadata contract: PASS — 6/6 focused tests and JSON parse/structured assertions.
- App-owned privacy manifest: PASS — 2/2 focused tests.
- Standard-only encryption and built Info.plist identity: PASS.
- Five canonical, opaque 1320 x 2868 real-UI screenshots: PASS — exact name/count, PNG format, dimensions, alpha, and original-resolution visual checks.
- Git diff check before evidence creation: PASS.

The focused public-page, metadata, and privacy-manifest run completed 16/16
tests. Those tests are included in the current 164-test Python total and are
listed separately to make the release contracts auditable; they are not added
again to the total.

## Screenshot evidence

All five assets are regular non-symlink PNG files with no alpha channel. Their
current SHA-256 values are:

| Order | File | SHA-256 |
| --- | --- | --- |
| 1 | `app-store-01-capture.png` | `545ff95e06341239d8da0feb9d29685843131860c4903b2307c5ba3223a190e1` |
| 2 | `app-store-02-summary.png` | `729c75cf036b4f7c3358be9c2e5cba26b6b4bce613082a1c94d9fa3162861aed` |
| 3 | `app-store-03-nutrition.png` | `71c5e07c62d99a0a491f059e038fed0db22de83898d2f30139761f4c712cd112` |
| 4 | `app-store-04-consent.png` | `8dc447c8d378b3469d5575adf6cedb1fbc470ebb20e66cc311d141c1267f6d83` |
| 5 | `app-store-05-uncertainty.png` | `f55cbc8ea553d1b6f11dccd573fb994a49f20ebe11d1deba0d86b067ba4f3cd9` |

The files show Japanese real UI in the approved functional order. Original-
resolution inspection found no fixture controls, personal images, identifiers,
secrets, provider responses, invented trend/history UI, clipping, safe-area
overlap, or transparency.

## Packaged pages versus production

- Local privacy page package: PASS.
- Local support page package: PASS.
- Read-only production check for the support URL: HTTP 404 on 2026-08-11.
- Read-only production check for the privacy-policy URL: HTTP 404 on 2026-08-11.
- Metadata state for both URLs: `PENDING_PRODUCTION`, with `http_200` and `content_verified` still `null`.

Local package tests do not make either production URL live. Neither URL is
accepted for App Store submission until a later deployment gate proves HTTP 200
and verifies the served content.

## Commands executed

```bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit, lib.app_check"
uv pip check --python .venv/bin/python
docker build .
npm run ios:localizations:check
xcodegen generate --spec ios/project.yml --project ios
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project ios/Kalories.xcodeproj \
  -scheme Kalories \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
scripts/check-ios-app-check-release.sh --local
.venv/bin/python -m unittest \
  tests.test_public_pages \
  tests.test_app_store_metadata \
  tests.test_ios_privacy_manifest \
  -v
.venv/bin/python -m json.tool docs/release/app-store/ja-JP.json
```

Additional local assertions parsed the structured metadata, source and built
Info.plists, Xcode build settings, screenshot files, and Xcode result summary.
A read-only `curl` status check was made for each production page. No deployment,
traffic, Apple, signing, upload, or review mutation was made.

## External boundaries

- Production deployment: NOT RUN.
- Cloud traffic mutation: NOT RUN.
- Production App Check/Firebase configuration verification: NOT RUN; UNVERIFIED.
- Production support/privacy content acceptance: UNVERIFIED; current paths return HTTP 404.
- Signed App Store archive: NOT RUN.
- Signed-archive privacy-manifest reconciliation: NOT RUN; UNVERIFIED.
- Distribution certificate/profile validation: NOT RUN; UNVERIFIED.
- App Store Connect metadata entry/readback: NOT RUN; UNVERIFIED.
- Japan age-rating readback for iOS 26 or later: NOT RUN; UNVERIFIED.
- Japan age-rating readback for earlier OS versions: NOT RUN; UNVERIFIED.
- App Store Connect upload: NOT RUN.
- App Review submission: NOT RUN.
- Automatic release trigger: NOT RUN.
- Japan storefront availability/download: NOT RUN; UNVERIFIED.

This ledger closes only the local foundation gate. It is not evidence of a
deployment, signed archive, upload, review approval, automatic release, or
downloadable App Store listing.
